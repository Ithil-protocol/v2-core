// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../interfaces/external/wizardex/IPool.sol";
import { IBalancerVault } from "../../interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/balancer/IBalancerPool.sol";
import { IProtocolFeesCollector } from "../../interfaces/external/balancer/IProtocolFeesCollector.sol";
import { IGauge } from "../../interfaces/external/balancer/IGauge.sol";
import { BalancerHelper } from "../../libraries/BalancerHelper.sol";
import { VaultHelper } from "../../libraries/VaultHelper.sol";
import { WeightedMath } from "../../libraries/external/Balancer/WeightedMath.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { Service } from "../Service.sol";
import { DebitService } from "../DebitService.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBalancerPool;

    struct PoolData {
        bytes32 balancerPoolID;
        address[] tokens;
        uint256[] weights;
        uint256[] scalingFactors;
        uint256 maximumWeightIndex;
        uint8 length;
        uint256 swapFee;
        address gauge;
        address protocolFeeCollector;
    }

    event PoolWasAdded(address indexed balancerPool);
    event PoolWasRemoved(address indexed balancerPool);

    error InexistentPool();
    error TokenIndexMismatch();
    error SlippageError();

    mapping(address => PoolData) public pools;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;
    address public immutable bal;
    IOracle public immutable oracle;
    IFactory public immutable dex;

    constructor(
        address _manager,
        address _oracle,
        address _factory,
        address _balancerVault,
        address _bal,
        uint256 _deadline
    ) Service("BalancerService", "BALANCER-SERVICE", _manager, _deadline) {
        oracle = IOracle(_oracle);
        dex = IFactory(_factory);
        balancerVault = IBalancerVault(_balancerVault);
        bal = _bal;
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert InexistentPool();

        uint256[] memory amountsIn = new uint256[](agreement.loans.length);
        address[] memory tokens = new address[](agreement.loans.length);

        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
            amountsIn[index] = agreement.loans[index].amount + agreement.loans[index].margin;
        }
        IERC20 bpToken = IERC20(agreement.collaterals[0].token);
        uint256 bptInitialBalance = bpToken.balanceOf(address(this));

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsIn,
                agreement.collaterals[0].amount
            ),
            fromInternalBalance: false
        });
        balancerVault.joinPool(pool.balancerPoolID, address(this), address(this), request);

        agreement.collaterals[0].amount = bpToken.balanceOf(address(this)) - bptInitialBalance;
        if (pool.gauge != address(0)) IGauge(pool.gauge).deposit(agreement.collaterals[0].amount);
    }

    function _close(uint256, /*tokenID*/ Agreement memory agreement, bytes memory data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        // TODO: add check on fees to be sure amountOut is not too little
        if (pool.gauge != address(0)) IGauge(pool.gauge).withdraw(agreement.collaterals[0].amount, true);
        address[] memory tokens = new address[](agreement.loans.length);
        (uint256[] memory minAmountsOut, bytes memory swapData) = abi.decode(data, (uint256[], bytes));
        bool slippageEnforced = true;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
            if (minAmountsOut[index] <= agreement.loans[index].amount) {
                slippageEnforced = false;
                minAmountsOut[index] = agreement.loans[index].amount;
            }
        }

        uint256 spentBpt = IERC20(agreement.collaterals[0].token).balanceOf(address(this));
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(2, minAmountsOut, agreement.collaterals[0].amount),
            toInternalBalance: false
        });
        // If possible, try to obtain the minAmountsOut
        try balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request) {
            spentBpt -= IERC20(agreement.collaterals[0].token).balanceOf(address(this));
            assert(spentBpt <= agreement.collaterals[0].amount);
        } catch {
            // It is not possible to obtain minAmountsOut
            // This could be a bad repay event but also a too strict slippage on user side
            // In the latter case, we simply revert
            if (slippageEnforced) revert SlippageError();
            spentBpt = 0;
        }
        // Swap residual BPT for whatever the Balancer pool gives back and repay sender
        // This is done also if slippage is not enforced and the first exit failed
        // In this case we are on a bad liquidation
        request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: new uint256[](agreement.loans.length),
            userData: abi.encode(1, agreement.collaterals[0].amount - spentBpt),
            toInternalBalance: false
        });
        balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request);
    }

    // bug: this quote has a branch which always returns zero
    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert InexistentPool();

        (, uint256[] memory totalBalances, ) = balancerVault.getPoolTokens(pool.balancerPoolID);
        uint256[] memory amountsOut = new uint256[](agreement.loans.length);
        uint256[] memory profits;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            amountsOut[index] = agreement.loans[index].amount;
        }
        // Calculate needed BPT to repay loan + fees
        uint256 bptAmountOut = _calculateExpectedBPTToExit(agreement.collaterals[0].token, totalBalances, amountsOut);
        // The remaining BPT is swapped to obtain profit
        // We need to update the balances since we virtually took tokens out of the pool
        // We also need to update the total supply since the bptOut were burned
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            totalBalances[index] -= amountsOut[index];
        }
        if (bptAmountOut < agreement.collaterals[0].amount) {
            profits = _calculateExpectedTokensFromBPT(
                agreement.collaterals[0].token,
                totalBalances,
                agreement.collaterals[0].amount - bptAmountOut,
                IERC20(agreement.collaterals[0].token).totalSupply() - bptAmountOut
            );
            // Besides spurious tokens, also amountsOut had been obtained at the first exit
            for (uint256 index = 0; index < agreement.loans.length; index++) {
                profits[index] += amountsOut[index];
            }
        }

        return profits;
    }

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external onlyOwner {
        assert(poolAddress != address(0));

        (address[] memory poolTokens, , ) = balancerVault.getPoolTokens(balancerPoolID);
        uint256 length = poolTokens.length;
        assert(length > 0);

        IBalancerPool bpool = IBalancerPool(poolAddress);
        bpool.approve(gauge, type(uint256).max);

        uint256 fee = bpool.getSwapFeePercentage();
        uint256[] memory weights = bpool.getNormalizedWeights();
        uint256 maxWeightTokenIndex = 0;
        uint256[] memory scalingFactors = new uint256[](length);

        for (uint8 i = 0; i < length; i++) {
            if (IERC20(poolTokens[i]).allowance(address(this), address(balancerVault)) == 0) {
                IERC20(poolTokens[i]).approve(address(balancerVault), type(uint256).max);
            }
            if (weights[i] > weights[maxWeightTokenIndex]) maxWeightTokenIndex = i;
            scalingFactors[i] = 10 ** (18 - IERC20Metadata(poolTokens[i]).decimals());
        }

        pools[poolAddress] = PoolData(
            balancerPoolID,
            poolTokens,
            weights,
            scalingFactors,
            maxWeightTokenIndex,
            uint8(length),
            fee,
            gauge,
            balancerVault.getProtocolFeesCollector()
        );

        emit PoolWasAdded(poolAddress);
    }

    function removePool(address poolAddress) external onlyOwner {
        PoolData memory pool = pools[poolAddress];
        assert(pools[poolAddress].length != 0);

        IERC20(poolAddress).approve(pool.gauge, 0);
        delete pools[poolAddress];

        emit PoolWasRemoved(poolAddress);
    }

    function harvest(address poolAddress) external {
        PoolData memory pool = pools[poolAddress];
        if (pool.length == 0) revert InexistentPool();

        IGauge(pool.gauge).claim_rewards(address(this));

        (address token, address vault) = VaultHelper.getBestVault(pool.tokens, manager);
        // TODO check oracle
        uint256 price = oracle.getPrice(bal, token, 1);
        address dexPool = dex.pools(bal, token, 10); // TODO hardcoded tick
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(bal).balanceOf(address(this)), price, vault, block.timestamp + 1 weeks);

        // TODO add premium to the caller
    }

    function _modifyBalancesWithFees(
        address poolAddress,
        uint256[] memory balances,
        uint256[] memory normalizedWeights
    ) internal view {
        PoolData memory pool = pools[poolAddress];

        for (uint256 i = 0; i < pool.length; i++) {
            balances[i] *= pool.scalingFactors[i];
        }

        uint256[] memory dueProtocolFeeAmounts = new uint256[](pool.length);
        dueProtocolFeeAmounts[pool.maximumWeightIndex] = WeightedMath._calcDueTokenProtocolSwapFeeAmount(
            balances[pool.maximumWeightIndex],
            normalizedWeights[pool.maximumWeightIndex],
            IBalancerPool(poolAddress).getLastInvariant(),
            WeightedMath._calculateInvariant(normalizedWeights, balances),
            IProtocolFeesCollector(pool.protocolFeeCollector).getSwapFeePercentage()
        );

        balances[pool.maximumWeightIndex] -= dueProtocolFeeAmounts[pool.maximumWeightIndex];
    }

    // Assumes balances are already upscaled and downscales them back together with balances
    function _calculateExpectedBPTToExit(
        address poolAddress,
        uint256[] memory balances,
        uint256[] memory amountsOut
    ) internal view returns (uint256) {
        PoolData memory pool = pools[poolAddress];
        uint256[] memory normalizedWeights = IBalancerPool(poolAddress).getNormalizedWeights();
        _modifyBalancesWithFees(poolAddress, balances, normalizedWeights);

        for (uint256 i = 0; i < pool.length; i++) {
            amountsOut[i] *= pool.scalingFactors[i];
        }

        uint256 expectedBpt = WeightedMath._calcBptInGivenExactTokensOut(
            balances,
            normalizedWeights,
            amountsOut,
            IERC20(poolAddress).totalSupply(),
            IBalancerPool(poolAddress).getSwapFeePercentage()
        );
        for (uint256 i = 0; i < pool.length; i++) {
            amountsOut[i] /= pool.scalingFactors[i];
            balances[i] /= pool.scalingFactors[i];
        }
        return expectedBpt;
    }

    // Assumes balances are already upscaled and downscales them back together with balances
    function _calculateExpectedTokensFromBPT(
        address poolAddress,
        uint256[] memory balances,
        uint256 amount,
        uint256 totalSupply
    ) internal view returns (uint256[] memory) {
        PoolData memory pool = pools[poolAddress];
        uint256[] memory normalizedWeights = IBalancerPool(poolAddress).getNormalizedWeights();
        _modifyBalancesWithFees(poolAddress, balances, normalizedWeights);
        uint256[] memory expectedTokens = WeightedMath._calcTokensOutGivenExactBptIn(balances, amount, totalSupply);

        for (uint256 i = 0; i < pool.length; i++) {
            expectedTokens[i] /= pool.scalingFactors[i];
            balances[i] /= pool.scalingFactors[i];
        }

        return expectedTokens;
    }
}
