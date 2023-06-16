// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/dex/IFactory.sol";
import { IPool } from "../../interfaces/external/dex/IPool.sol";
import { ICurvePool } from "../../interfaces/external/curve/ICurvePool.sol";
import { IConvexBooster } from "../../interfaces/external/convex/IConvexBooster.sol";
import { IBaseRewardPool } from "../../interfaces/external/convex/IBaseRewardPool.sol";
import { CurveHelper } from "../../libraries/CurveHelper.sol";
import { VaultHelper } from "../../libraries/VaultHelper.sol";
import { ConstantRateModel } from "../../irmodels/ConstantRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    CurveConvexService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Curve pool plus staking on Convex
contract CurveConvexService is Whitelisted, ConstantRateModel, DebitService {
    using SafeERC20 for IERC20;

    struct PoolData {
        address curve; // Curve pool address
        uint256 convex; // Convex pool ID
        IBaseRewardPool baseRewardPool; // Convex rewards pool
        address[] tokens;
        address[] rewardTokens; // Incentive tokens given by Curve
    }

    event PoolWasAdded(address indexed curvePool, uint256 indexed convexPid);
    event PoolWasRemoved(address indexed curvePool, uint256 indexed convexPid);

    error InexistentPool();
    error TokenIndexMismatch();
    error ConvexStakingFailed();

    mapping(address => PoolData) public pools;
    IConvexBooster internal immutable booster;
    address internal immutable crv;
    address internal immutable cvx;
    IOracle public immutable oracle;
    IFactory public immutable factory;

    constructor(
        address _manager,
        address _oracle,
        address _factory,
        address _booster,
        address _crv,
        address _cvx,
        uint256 _deadline
    ) Service("CurveConvexService", "CURVECONVEX-SERVICE", _manager, _deadline) {
        oracle = IOracle(_oracle);
        factory = IFactory(_factory);
        booster = IConvexBooster(_booster);
        cvx = _cvx;
        crv = _crv;
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.tokens.length == 0) revert InexistentPool();

        CurveHelper.deposit(pool.curve, agreement);

        agreement.collaterals[0].amount = IERC20(agreement.collaterals[0].token).balanceOf(address(this));

        if (!booster.deposit(pool.convex, agreement.collaterals[0].amount)) revert ConvexStakingFailed();
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];

        pool.baseRewardPool.withdraw(agreement.collaterals[0].amount, false);

        CurveHelper.withdraw(pool.curve, agreement, data);

        // transfer spurious reward tokens to the user
        IConvexBooster.PoolInfo memory poolInfo = booster.poolInfo(pool.convex);
        pool.baseRewardPool.getReward(address(this));
        // Total base rewards token
        // TODO check if they are 1:1 with base LP Curve tokens, this is the sum of all collaterals
        uint256 totalOwnership = IERC20(poolInfo.rewards).balanceOf(address(this));

        if (totalOwnership > 0)
            for (uint8 i = 0; i < pool.rewardTokens.length; i++) {
                IERC20 token = IERC20(pool.rewardTokens[i]);

                token.safeTransfer(
                    msg.sender,
                    (token.balanceOf(address(this)) * agreement.collaterals[0].amount) / totalOwnership
                );
            }
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.tokens.length == 0) revert InexistentPool();

        uint256[] memory quoted = new uint256[](agreement.loans.length);
        uint256[] memory balances = CurveHelper.getBalances(pool.curve, agreement.loans.length);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            // This is literally Curve's code, therefore we do NOT use GeneralMath
            quoted[index] =
                (balances[index] * agreement.collaterals[0].amount) /
                IERC20(agreement.collaterals[0].token).totalSupply();
        }

        return quoted;
    }

    function addPool(address curvePool, uint256 convexPid, address[] calldata tokens) external onlyOwner {
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

        // Add reward tokens
        IBaseRewardPool rewardPool = IBaseRewardPool(poolInfo.rewards);
        length = rewardPool.rewardLength();
        address[] memory rewardTokens = new address[](length);
        for (uint256 i = 0; i < length; i++) rewardTokens[i] = rewardPool.rewards(i);

        pools[poolInfo.lptoken] = PoolData(curvePool, convexPid, rewardPool, tokens, rewardTokens);

        emit PoolWasAdded(curvePool, convexPid);
    }

    function removePool(address token) external onlyOwner {
        PoolData memory pool = pools[token];
        if (pool.tokens.length == 0) revert InexistentPool();

        uint256 length = pool.tokens.length;
        for (uint256 i = 0; i < length; i++) {
            // Remove Curve pool allowance
            IERC20(pool.tokens[i]).approve(pool.curve, 0);
        }

        delete pools[token];

        emit PoolWasRemoved(pool.curve, pool.convex);
    }

    function harvest(address _token) external {
        PoolData memory pool = pools[_token];
        if (pool.tokens.length == 0) revert InexistentPool();

        pool.baseRewardPool.getReward(address(this));

        (address token, address vault) = VaultHelper.getBestVault(pool.tokens, manager);

        // TODO check oracle
        uint256 price = oracle.getPrice(crv, token, 1);
        address dexPool = factory.pools(crv, token);
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(crv).balanceOf(address(this)), price, vault, block.timestamp + 30 days);

        // TODO check oracle
        price = oracle.getPrice(cvx, token, 1);
        dexPool = factory.pools(cvx, token);
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(cvx).balanceOf(address(this)), price, vault, block.timestamp + 30 days);

        // TODO add premium to the caller
    }
}
