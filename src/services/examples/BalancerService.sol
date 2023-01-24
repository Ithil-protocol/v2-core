// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBalancerVault } from "../../interfaces/external/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/IBalancerPool.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { BalancerHelper } from "../../libraries/BalancerHelper.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is SecuritisableService {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    struct PoolData {
        bytes32 balancerPoolID;
        address[] tokens;
        uint256[] weights;
        uint8 length;
        uint256 swapFee;
    }

    event PoolWasAdded(address indexed balancerPool);
    event PoolWasRemoved(address indexed balancerPool);

    error BalancerStrategy__Inexistent_Pool(address balancerPool);
    error BalancerStrategy__Token_Index_Mismatch(uint256 tokenIndex);

    mapping(address => PoolData) public pools;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;

    constructor(address _manager, address _balancerVault) Service("BalancerService", "BALANCER-SERVICE", _manager) {
        balancerVault = IBalancerVault(_balancerVault);
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert BalancerStrategy__Inexistent_Pool(agreement.collaterals[0].token);

        uint256[] memory amountsIn = new uint256[](agreement.loans.length);
        address[] memory tokens = new address[](agreement.loans.length);

        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert BalancerStrategy__Token_Index_Mismatch(index);
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
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        address[] memory tokens;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert BalancerStrategy__Token_Index_Mismatch(index);
        }

        uint256[] memory minAmountsOut = abi.decode(data, (uint256[]));

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, agreement.collaterals[0].amount),
            toInternalBalance: false
        });

        balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request);
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert BalancerStrategy__Inexistent_Pool(agreement.collaterals[0].token);
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

    function addPool(address poolAddress, bytes32 balancerPoolID) external onlyOwner {
        (address[] memory poolTokens, , ) = balancerVault.getPoolTokens(balancerPoolID);
        uint256 length = poolTokens.length;
        assert(length > 0);

        IBalancerPool bpool = IBalancerPool(poolAddress);
        uint256 fee = bpool.getSwapFeePercentage();
        uint256[] memory weights = bpool.getNormalizedWeights();

        for (uint8 i = 0; i < length; i++) {
            if (IERC20(poolTokens[i]).allowance(address(this), address(balancerVault)) == 0)
                IERC20(poolTokens[i]).safeApprove(address(balancerVault), type(uint256).max);
        }

        pools[poolAddress] = PoolData(balancerPoolID, poolTokens, weights, uint8(length), fee);

        emit PoolWasAdded(poolAddress);
    }

    function removePool(address poolAddress) external onlyOwner {
        PoolData memory pool = pools[poolAddress];
        delete pools[poolAddress];

        for (uint8 i = 0; i < pool.tokens.length; i++) {
            IERC20 token = IERC20(pool.tokens[i]);
            token.approve(address(balancerVault), 0);
        }

        emit PoolWasRemoved(poolAddress);
    }
}
