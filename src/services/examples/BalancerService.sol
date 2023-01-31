// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBalancerVault } from "../../interfaces/external/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/IBalancerPool.sol";
import { IGauge } from "../../interfaces/external/IGauge.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { BalancerHelper } from "../../libraries/BalancerHelper.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

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
        IGauge(pool.gauge).deposit(agreement.collaterals[0].amount);
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        // TODO: add check on fees to be sure amountOut is not too little
        IGauge(pool.gauge).withdraw(agreement.collaterals[0].amount, true);
        address[] memory tokens = new address[](agreement.loans.length);
        uint256[] memory minAmountsOut = abi.decode(data, (uint256[]));
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
        }

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(2, minAmountsOut, agreement.collaterals[0].amount),
            toInternalBalance: false
        });

        uint256 spentBpt = IERC20(agreement.collaterals[0].token).balanceOf(address(this));
        balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request);
        spentBpt -= IERC20(agreement.collaterals[0].token).balanceOf(address(this));
        // Swap residual BPT for whatever the Balancer pool gives back and repay sender
        request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: new uint256[](agreement.loans.length),
            userData: abi.encode(1, agreement.collaterals[0].amount - spentBpt),
            toInternalBalance: false
        });
        balancerVault.exitPool(pool.balancerPoolID, address(this), payable(msg.sender), request);
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert InexistentPool();
        (address[] memory tokens, uint256[] memory totalBalances, ) = balancerVault.getPoolTokens(pool.balancerPoolID);

        uint256 collateral = agreement.collaterals[0].amount;
        uint256 tokenIndex = 0;
        uint256 assignedIndex = 0;
        uint256[] memory fees = new uint256[](agreement.loans.length);
        uint256[] memory quoted = new uint256[](agreement.loans.length);
        for (; tokenIndex < agreement.loans.length; tokenIndex++) {
            assignedIndex = BalancerHelper.getTokenIndex(tokens, agreement.loans[tokenIndex].token);
            (uint256 interest, uint256 spread) = agreement.loans[tokenIndex].interestAndSpread.unpackUint();
            fees[tokenIndex] = agreement.loans[tokenIndex].amount.safeMulDiv(interest + spread, GeneralMath.RESOLUTION);
            if (collateral > 0) {
                uint256 bptNeeded = BalancerHelper.computeBptOut(
                    agreement.loans[tokenIndex].amount + fees[tokenIndex],
                    IERC20(agreement.collaterals[0].token).totalSupply(),
                    totalBalances[assignedIndex],
                    pool.weights[assignedIndex],
                    pool.swapFee
                );
                if (bptNeeded <= collateral) {
                    // The collateral is enough to pay the loan for tokenIndex: quoting this is enough
                    quoted[tokenIndex] = agreement.loans[tokenIndex].amount + fees[tokenIndex];
                    collateral -= bptNeeded;
                } else {
                    // The collateral is not enough to pay the loan for tokenIndex: we compute the last quote
                    // We cannot break the loop because we still need to compute the fees
                    quoted[tokenIndex] = BalancerHelper.computeAmountOut(
                        collateral,
                        IERC20(agreement.collaterals[0].token).totalSupply(),
                        totalBalances[assignedIndex],
                        pool.weights[assignedIndex],
                        pool.swapFee
                    );
                    collateral = 0;
                }
            }
        }
        // If at this point we have positive collateral, the position is gaining and we add to the last index
        assignedIndex = BalancerHelper.getTokenIndex(tokens, agreement.loans[tokenIndex - 1].token);
        quoted[tokenIndex - 1] += BalancerHelper.computeAmountOut(
            collateral,
            IERC20(agreement.collaterals[0].token).totalSupply(),
            totalBalances[assignedIndex],
            pool.weights[assignedIndex],
            pool.swapFee
        );

        return (quoted, fees);
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
