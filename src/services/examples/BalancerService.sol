// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBalancerVault } from "../../interfaces/external/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/IBalancerPool.sol";
import { IGauge } from "../../interfaces/external/IGauge.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { BalancerHelper } from "../../libraries/BalancerHelper.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

import { WeightedMath } from "../../libraries/external/Balancer/WeightedMath.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is SecuritisableService {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IBalancerPool;

    struct PoolData {
        bytes32 balancerPoolID;
        address[] tokens;
        uint256[] weights;
        uint8 length;
        uint256 swapFee;
        address gauge;
    }

    event PoolWasAdded(address indexed balancerPool);
    event PoolWasRemoved(address indexed balancerPool);

    error InexistentPool();
    error TokenIndexMismatch();
    error SlippageError();

    mapping(address => PoolData) public pools;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;
    address public immutable rewardToken;

    constructor(address _manager, address _balancerVault, address _rewardToken)
        Service("BalancerService", "BALANCER-SERVICE", _manager)
    {
        balancerVault = IBalancerVault(_balancerVault);
        rewardToken = _rewardToken;
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
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

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        // TODO: add check on fees to be sure amountOut is not too little
        if (pool.gauge != address(0)) IGauge(pool.gauge).withdraw(agreement.collaterals[0].amount, true);
        address[] memory tokens = new address[](agreement.loans.length);
        uint256[] memory minAmountsOut = abi.decode(data, (uint256[]));
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
        } catch {
            // It is not possible to obtain minAmountsOut
            // This could be a bad repay event but also a too strict slippage on user side
            // In the latter case, we simply revert
            if (slippageEnforced) revert SlippageError();
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

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert InexistentPool();
        (, uint256[] memory totalBalances, ) = balancerVault.getPoolTokens(pool.balancerPoolID);
        uint256[] memory amountsOut = new uint256[](agreement.loans.length);
        uint256[] memory fees = new uint256[](agreement.loans.length);
        uint256[] memory profits;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            // TODO: add fees
            amountsOut[index] = agreement.loans[index].amount;
        }
        // Calculate needed BPT to repay loan + fees
        uint256 totalSupply = IERC20(agreement.collaterals[0].token).totalSupply();
        uint256 bptAmountOut = WeightedMath._calcBptInGivenExactTokensOut(
            totalBalances,
            pool.weights,
            amountsOut,
            totalSupply,
            pool.swapFee
        );
        // The remaining BPT is swapped to obtain profit
        // We need to update the balances since we virtually took tokens out of the pool
        // We also need to update the total supply since the bptOut were burned
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            // TODO: add fees
            totalBalances[index] -= amountsOut[index];
        }
        if (bptAmountOut < agreement.collaterals[0].amount) {
            profits = BalancerHelper.exitExactBPTInForTokensOut(
                totalBalances,
                agreement.collaterals[0].amount - bptAmountOut,
                totalSupply - bptAmountOut
            );
        }
        return (profits, fees);
    }

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external onlyOwner {
        assert(poolAddress != address(0));

        (address[] memory poolTokens, , ) = balancerVault.getPoolTokens(balancerPoolID);
        uint256 length = poolTokens.length;
        assert(length > 0);

        IBalancerPool bpool = IBalancerPool(poolAddress);
        bpool.safeApprove(gauge, type(uint256).max);

        uint256 fee = bpool.getSwapFeePercentage();
        uint256[] memory weights = bpool.getNormalizedWeights();

        for (uint8 i = 0; i < length; i++) {
            if (IERC20(poolTokens[i]).allowance(address(this), address(balancerVault)) == 0)
                IERC20(poolTokens[i]).safeApprove(address(balancerVault), type(uint256).max);
        }

        pools[poolAddress] = PoolData(balancerPoolID, poolTokens, weights, uint8(length), fee, gauge);

        emit PoolWasAdded(poolAddress);
    }

    function removePool(address poolAddress) external onlyOwner {
        PoolData memory pool = pools[poolAddress];
        assert(pools[poolAddress].length != 0);

        IERC20(poolAddress).approve(pool.gauge, 0);
        delete pools[poolAddress];

        emit PoolWasRemoved(poolAddress);
    }
}
