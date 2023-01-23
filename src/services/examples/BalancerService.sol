// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBalancerVault } from "../../interfaces/external/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/IBalancerPool.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is SecuritisableService {
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

    error InexistentPool();
    error TokenIndexMismatch();

    mapping(address => PoolData) public pools;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;

    constructor(address _manager, address _balancerVault) Service("BalancerService", "BALANCER-SERVICE", _manager) {
        balancerVault = IBalancerVault(_balancerVault);
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
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        address[] memory tokens;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
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

    function addPool(address poolAddress, bytes32 balancerPoolID) external onlyOwner {
        assert(poolAddress != address(0));

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
        assert(pools[poolAddress].length != 0);

        delete pools[poolAddress];

        emit PoolWasRemoved(poolAddress);
    }
}
