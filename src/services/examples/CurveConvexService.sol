// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurvePool } from "../../interfaces/external/ICurvePool.sol";
import { IConvexBooster } from "../../interfaces/external/IConvexBooster.sol";
import { IBaseRewardPool } from "../../interfaces/external/IBaseRewardPool.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

/// @title    CurveConvexService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Curve pool plus staking on Convex
contract CurveConvexService is SecuritisableService {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    struct PoolData {
        address curve; // Curve pool address
        uint256 convex; // Convex pool ID
        IBaseRewardPool baseRewardPool; // Convex rewards pool
        address[] tokens;
    }

    event PoolWasAdded(address indexed curvePool, uint256 indexed ConvexPid);
    event PoolWasRemoved(address indexed curvePool, uint256 indexed ConvexPid);

    error InexistentPool();
    error TokenIndexMismatch();
    error ConvexStakingFailed();

    mapping(address => PoolData) public pools;
    IConvexBooster internal immutable booster;
    IERC20 internal immutable crv;
    IERC20 internal immutable cvx;

    constructor(address _manager, address _booster, address _cvx)
        Service("BalancerService", "BALANCER-SERVICE", _manager)
    {
        booster = IConvexBooster(_booster);
        cvx = IERC20(_cvx);
        crv = IERC20(booster.crv());
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.tokens.length == 0) revert InexistentPool();

        if (agreement.loans.length == 2) {
            uint256[2] memory amounts;
            for (uint256 index = 0; index < 2; index++) {
                amounts[index] = agreement.loans[index].amount + agreement.loans[index].margin;
            }
            ICurvePool(pool.curve).add_liquidity(amounts, agreement.collaterals[0].amount);
        } else if (agreement.loans.length == 3) {
            uint256[3] memory amounts;
            for (uint256 index = 0; index < 3; index++) {
                amounts[index] = agreement.loans[index].amount + agreement.loans[index].margin;
            }
            ICurvePool(pool.curve).add_liquidity(amounts, agreement.collaterals[0].amount);
        } else {
            revert InexistentPool();
        }

        agreement.collaterals[0].amount = IERC20(agreement.collaterals[0].token).balanceOf(address(this));

        if (!booster.deposit(pool.convex, agreement.collaterals[0].amount, true)) revert ConvexStakingFailed();
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        pool.baseRewardPool.withdrawAndUnwrap(agreement.collaterals[0].amount, false);

        if (agreement.loans.length == 2) {
            uint256[2] memory minAmountsOut = abi.decode(data, (uint256[2]));
            ICurvePool(pool.curve).remove_liquidity(agreement.collaterals[0].amount, minAmountsOut);
        } else if (agreement.loans.length == 3) {
            uint256[3] memory minAmountsOut = abi.decode(data, (uint256[3]));
            ICurvePool(pool.curve).remove_liquidity(agreement.collaterals[0].amount, minAmountsOut);
        }
    }

    function addPool(address curvePool, uint256 convexPid, address[] calldata tokens) external onlyOwner {
        IConvexBooster.PoolInfo memory poolInfo = booster.poolInfo(convexPid);
        assert(!poolInfo.shutdown);

        ICurvePool curve = ICurvePool(curvePool);
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            assert(curve.coins(i) == tokens[i]);

            // Allow Curve pool to take tokens
            IERC20(tokens[i]).safeApprove(curvePool, type(uint256).max);
        }

        // Allow Convex to take Curve LP tokens
        IERC20(poolInfo.lptoken).safeApprove(address(booster), type(uint256).max);

        pools[poolInfo.lptoken] = PoolData(curvePool, convexPid, IBaseRewardPool(poolInfo.crvRewards), tokens);

        emit PoolWasAdded(curvePool, convexPid);
    }

    function removePool(address token) external onlyOwner {
        PoolData memory pool = pools[token];
        if (pool.tokens.length == 0) revert InexistentPool();

        ICurvePool curve = ICurvePool(pool.curve);
        uint256 length = pool.tokens.length;
        for (uint256 i = 0; i < length; i++) {
            // Remove Curve pool allowance
            IERC20(pool.tokens[i]).approve(pool.curve, 0);
        }

        delete pools[token];

        emit PoolWasRemoved(pool.curve, pool.convex);
    }

    /*
    CurvePool memory p = pools[token];
    if (pools[token].pool == address(0)) revert CurveStrategy__Token_Not_Supported();

    p.baseRewardPool.getReward(address(this), true);

    function quote(address src, address dst, uint256 amount) public view override returns (uint256, uint256) {
        ICurve pool = ICurve(pools[src].pool);
        uint256 obtained = (amount * 10**36) / pool.get_virtual_price();
        return (obtained, obtained);
    }
    */
}
