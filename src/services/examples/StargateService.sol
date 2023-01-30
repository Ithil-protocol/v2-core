// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStargateRouter } from "../../interfaces/external/IStargateRouter.sol";
import { IStargateLPStaking, IStargatePool } from "../../interfaces/external/IStargateLPStaking.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

/// @title    StargateService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Stargate pool
contract StargateService is SecuritisableService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IStargatePool;

    struct PoolData {
        uint16 poolID;
        uint256 stakingPoolID;
        address lpToken;
        bool locked;
    }
    IStargateRouter public immutable stargateRouter;
    IStargateLPStaking public immutable stargateLPStaking;
    IERC20 public immutable stargate;
    mapping(address => PoolData) public pools;
    mapping(address => uint256) public totalDeposits;

    event PoolWasAdded(address indexed token);
    event PoolLockWasToggled(address indexed token, bool status);
    error InexistentPool();

    constructor(address _manager, address _stargateRouter, address _stargateLPStaking)
        Service("StargateService", "STARGATE-SERVICE", _manager)
    {
        stargateRouter = IStargateRouter(_stargateRouter);
        stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
        stargate = IERC20(stargateLPStaking.stargate());
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        if (pools[agreement.loans[0].token].poolID == 0) revert InexistentPool();

        PoolData memory pool = pools[agreement.loans[0].token];

        stargateRouter.addLiquidity(pool.poolID, agreement.loans[0].amount + agreement.loans[0].margin, address(this));
        agreement.collaterals[0].amount = IERC20(pool.lpToken).balanceOf(address(this));

        uint256 initialBalance = stargate.balanceOf(address(this));
        stargateLPStaking.deposit(pool.stakingPoolID, agreement.collaterals[0].amount);

        // update harvests data
        //harvests[pool.poolID].totalRewards[0] += stargate.balanceOf(address(this)) - initialBalance;
        //harvests[pool.poolID].totalStakedAmount += agreement.collaterals[0].amount;
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        PoolData memory pool = pools[agreement.loans[0].token];

        uint256 initialBalance = stargate.balanceOf(address(this));
        stargateLPStaking.withdraw(pool.stakingPoolID, agreement.collaterals[0].amount);
        //harvests[pool.poolID].totalRewards[0] -= initialBalance - stargate.balanceOf(address(this));
        //harvests[pool.poolID].totalStakedAmount -= agreement.collaterals[0].amount;

        stargateRouter.instantRedeemLocal(
            pools[agreement.loans[0].token].poolID,
            agreement.collaterals[0].amount,
            address(this)
        );

        /*
        bool harvest = abi.decode(data, (bool));
        if(harvest) {
            bytes memory poolID = abi.encode(agreement.loans[0].token);
            collectRewards(poolID);
        }
        */
    }

    /*
    function collectRewards(bytes memory data) public override {
        address token = abi.decode(data, (address));
        PoolData memory pool = pools[token];
        assert(pool.poolID != 0);

        uint256 initialBalance = stargate.balanceOf(address(this));
        stargateLPStaking.deposit(pool.stakingPoolID, 0);
        harvests[pool.poolID].totalRewards[0] += stargate.balanceOf(address(this)) - initialBalance;

        //_swap();
    }
    */

    function addPool(address token, uint256 stakingPoolID) external onlyOwner {
        assert(token != address(0));

        (address lpToken, , , ) = stargateLPStaking.poolInfo(stakingPoolID);
        IStargatePool pool = IStargatePool(lpToken);
        // check that the token provided and staking pool ID are correct
        assert(token == pool.token());

        pools[token] = PoolData({
            poolID: uint16(pool.poolId()),
            stakingPoolID: stakingPoolID,
            lpToken: lpToken,
            locked: false
        });
        //harvests[pools[token].poolID].totalRewards.push(0);

        // Approval for the main token
        if (IERC20(token).allowance(address(this), address(stargateRouter)) == 0)
            IERC20(token).safeApprove(address(stargateRouter), type(uint256).max);
        // Approval for the lpToken
        if (pool.allowance(address(this), address(stargateLPStaking)) == 0)
            pool.safeApprove(address(stargateLPStaking), type(uint256).max);

        emit PoolWasAdded(token);
    }

    function togglePoolLock(address token) external onlyOwner {
        assert(pools[token].poolID != 0);
        pools[token].locked = !pools[token].locked;

        // Reset token approvals
        IERC20(token).approve(address(stargateRouter), 0);
        IERC20(pools[token].lpToken).approve(address(stargateLPStaking), 0);

        emit PoolLockWasToggled(token, pools[token].locked);
    }
}
