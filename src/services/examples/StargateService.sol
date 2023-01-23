// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStargateRouter } from "../../interfaces/external/IStargateRouter.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

/// @title    StargateService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Stargate pool
contract StargateService is SecuritisableService {
    using SafeERC20 for IERC20;

    IStargateRouter public immutable stargate;
    mapping(address => uint16) public pools;

    event PoolWasAdded(uint16 indexed poolID);
    event PoolWasRemoved(uint16 indexed poolID);

    error InexistentPool();

    constructor(address _manager, address _stargate) Service("StargateService", "STARGATE-SERVICE", _manager) {
        stargate = IStargateRouter(_stargate);
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        if (pools[agreement.loans[0].token] == 0) revert InexistentPool();

        IERC20 lpToken = IERC20(agreement.collaterals[0].token);
        uint256 lpInitialBalance = lpToken.balanceOf(address(this));
        console2.log("Ciao");
        stargate.addLiquidity(
            pools[agreement.loans[0].token],
            agreement.loans[0].amount + agreement.loans[0].margin,
            address(this)
        );
        console2.log("Mondo");
        console2.log(lpToken.balanceOf(address(this)) - lpInitialBalance);
        agreement.collaterals[0].amount = lpToken.balanceOf(address(this)) - lpInitialBalance;
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata /*data*/) internal override {
        stargate.instantRedeemLocal(pools[agreement.loans[0].token], agreement.collaterals[0].amount, address(this));
    }

    function addPool(address token, uint16 poolID) external onlyOwner {
        assert(token != address(0));
        pools[token] = poolID;
        if (IERC20(token).allowance(address(this), address(stargate)) == 0)
            IERC20(token).safeApprove(address(stargate), type(uint256).max);

        emit PoolWasAdded(poolID);
    }

    function removePool(address token) external onlyOwner {
        assert(pools[token] != 0);
        emit PoolWasRemoved(pools[token]);

        IERC20(token).approve(address(stargate), 0);
        delete pools[token];
    }
}
