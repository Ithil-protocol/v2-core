// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurvePool } from "../../interfaces/external/curve/ICurvePool.sol";
import { IConvexBooster } from "../../interfaces/external/convex/IConvexBooster.sol";
import { IBaseRewardPool } from "../../interfaces/external/convex/IBaseRewardPool.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { CurveHelper } from "../../libraries/CurveHelper.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

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
        address[] rewardTokens; // Incentive tokens given by Curve
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

    constructor(address _manager, address _booster, address _crv, address _cvx)
        Service("CurveConvexService", "CURVECONVEX-SERVICE", _manager)
    {
        booster = IConvexBooster(_booster);
        cvx = IERC20(_cvx);
        crv = IERC20(_crv);
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.tokens.length == 0) revert InexistentPool();

        CurveHelper.deposit(pool.curve, agreement);

        agreement.collaterals[0].amount = IERC20(agreement.collaterals[0].token).balanceOf(address(this));

        if (!booster.deposit(pool.convex, agreement.collaterals[0].amount)) revert ConvexStakingFailed();
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        _harvest(pool, agreement.loans[0].token); /// @todo loans[0] or loans[n]?

        pool.baseRewardPool.withdrawAndUnwrap(agreement.collaterals[0].amount, false);

        CurveHelper.withdraw(pool.curve, agreement, data);
    }

    function _harvest(PoolData memory pool, address wanted) internal {
        pool.baseRewardPool.getReward(address(this), true);

        for (uint8 i = 0; i < pool.rewardTokens.length; i++) {
            /// @todo swap reward for notional
        }
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        uint256[] memory quoted = new uint256[](agreement.loans.length);
        uint256[] memory fees = new uint256[](agreement.loans.length);
        uint256[] memory balances = CurveHelper.getBalances(pool.curve, agreement.loans.length);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            // This is literally Curve's code, therefore we do NOT use GeneralMath
            quoted[index] =
                (balances[index] * agreement.collaterals[0].amount) /
                IERC20(agreement.collaterals[0].token).totalSupply();
        }
        return (quoted, fees);
    }

    function addPool(address curvePool, uint256 convexPid, address[] calldata tokens, address[] calldata rewardTokens)
        external
        onlyOwner
    {
        IConvexBooster.PoolInfo memory poolInfo = booster.poolInfo(convexPid);
        assert(!poolInfo.shutdown);

        ICurvePool curve = ICurvePool(curvePool);
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            try curve.coins(i) returns (address tkn) {
                assert(tkn == tokens[i]);
            } catch {
                int128 j = int128(uint128(i));
                assert(curve.coins(j) == tokens[i]);
            }

            // Allow Curve pool to take tokens
            IERC20(tokens[i]).safeApprove(curvePool, type(uint256).max);
        }

        // Allow Convex to take Curve LP tokens
        IERC20(poolInfo.lptoken).safeApprove(address(booster), type(uint256).max);

        pools[poolInfo.lptoken] = PoolData(
            curvePool,
            convexPid,
            IBaseRewardPool(poolInfo.rewards),
            tokens,
            rewardTokens
        );

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
    function quote(uint256 amount) public view override returns (uint256) {
        PoolData memory pool = pools[token];
        if (pool.tokens.length == 0) revert InexistentPool();

        return CurveHelper.quote(pool.curve, amount);
    }
    */
}
