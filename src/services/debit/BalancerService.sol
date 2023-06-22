// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IBalancerPoolManager } from "../../interfaces/IBalancerPoolManager.sol";
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
import { BalancerPoolManager } from "./utils/BalancerPoolManager.sol";
import { Service } from "../Service.sol";
import { DebitService } from "../DebitService.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBalancerPool;

    error InexistentPool();
    error TokenIndexMismatch();
    error SlippageError();

    IBalancerPoolManager internal immutable poolManager;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;
    address public immutable bal;
    IOracle public immutable oracle;
    IFactory public immutable dex;
    mapping(address => IBalancerPoolManager.PoolData) public pools;

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

        poolManager = new BalancerPoolManager(_balancerVault);
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        IBalancerPoolManager.PoolData memory pool = poolManager.getPool(agreement.collaterals[0].token);

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

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        IBalancerPoolManager.PoolData memory pool = poolManager.getPool(agreement.collaterals[0].token);

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

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        IBalancerPoolManager.PoolData memory pool = poolManager.getPool(agreement.collaterals[0].token);

        (, uint256[] memory totalBalances, ) = balancerVault.getPoolTokens(pool.balancerPoolID);
        uint256[] memory amountsOut = new uint256[](agreement.loans.length);
        uint256[] memory profits;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            amountsOut[index] = agreement.loans[index].amount;
        }
        // Calculate needed BPT to repay loan + fees
        uint256 bptAmountOut = BalancerHelper.calculateExpectedBPTToExit(
            agreement.collaterals[0].token,
            totalBalances,
            amountsOut,
            pool.scalingFactors,
            pool.protocolFeeCollector,
            pool.maximumWeightIndex
        );

        // The remaining BPT is swapped to obtain profit
        // We need to update the balances since we virtually took tokens out of the pool
        // We also need to update the total supply since the bptOut were burned
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            totalBalances[index] -= amountsOut[index];
        }
        if (bptAmountOut < agreement.collaterals[0].amount) {
            profits = BalancerHelper.calculateExpectedTokensFromBPT(
                agreement.collaterals[0].token,
                pool.protocolFeeCollector,
                totalBalances,
                pool.scalingFactors,
                pool.weights,
                pool.maximumWeightIndex,
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

    function harvest(address poolAddress) external {
        IBalancerPoolManager.PoolData memory pool = poolManager.getPool(poolAddress);
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

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external onlyOwner {
        // We need a delegate call as we are giving tokens approvals
        address(poolManager).delegatecall(
            abi.encodeWithSelector(IBalancerPoolManager.addPool.selector, poolAddress, balancerPoolID, gauge)
        );
    }

    function removePool(address poolAddress) external onlyOwner {
        address(poolManager).delegatecall(
            abi.encodeWithSelector(IBalancerPoolManager.removePool.selector, poolAddress)
        );
    }
}
