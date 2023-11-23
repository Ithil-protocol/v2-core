// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    AngleService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking of agEur on Angle
contract AngleService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    IERC4626 public immutable stEur;
    IERC20 public immutable agEur;

    error IncorrectProvidedToken();
    error IncorrectObtainedToken();
    error InsufficientAmountOut();
    error ZeroCollateral();

    constructor(
        address _manager,
        address _steur,
        uint256 _deadline
    ) Service("AngleService", "ANGLE-SERVICE", _manager, _deadline) {
        stEur = IERC4626(_steur);
        agEur = IERC20(stEur.asset());
        agEur.approve(address(stEur), type(uint256).max);
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override onlyWhitelisted {
        if (agreement.loans[0].token != address(agEur)) revert IncorrectProvidedToken();
        if (agreement.collaterals[0].token != address(stEur)) revert IncorrectObtainedToken();

        uint256 initialBalance = stEur.balanceOf(address(this));
        stEur.deposit(agreement.loans[0].amount + agreement.loans[0].margin, address(this));
        uint256 computedCollateral = stEur.balanceOf(address(this)) - initialBalance;

        if (computedCollateral < agreement.collaterals[0].amount) revert InsufficientAmountOut();
        agreement.collaterals[0].amount = computedCollateral;
    }

    function _close(uint256, /*tokenID*/ Agreement memory agreement, bytes memory data) internal override {
        uint256 minimumAmountOut = abi.decode(data, (uint256));
        uint256 amountIn = stEur.redeem(agreement.collaterals[0].amount, address(this), address(this));
        if (amountIn < minimumAmountOut) revert InsufficientAmountOut();
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory toRedeem = new uint256[](1);
        toRedeem[0] = stEur.convertToAssets(agreement.collaterals[0].amount);

        return toRedeem;
    }
}
