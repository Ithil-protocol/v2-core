// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    FraxlendService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking of FRAX on Fraxlend
contract FraxlendService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    IERC4626 public immutable fraxLend;
    IERC20 public immutable frax;

    error IncorrectProvidedToken();
    error IncorrectObtainedToken();
    error InsufficientAmountOut();
    error ZeroCollateral();

    constructor(
        address _manager,
        address _fraxLend,
        uint256 _deadline
    ) Service("FraxlendService", "FRAXLEND-SERVICE", _manager, _deadline) {
        fraxLend = IERC4626(_fraxLend);
        frax = IERC20(fraxLend.asset());
        frax.approve(address(fraxLend), type(uint256).max);
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override onlyWhitelisted {
        if (agreement.loans[0].token != address(frax)) revert IncorrectProvidedToken();
        if (agreement.collaterals[0].token != address(fraxLend)) revert IncorrectObtainedToken();

        uint256 initialBalance = fraxLend.balanceOf(address(this));
        fraxLend.deposit(agreement.loans[0].amount + agreement.loans[0].margin, address(this));
        uint256 computedCollateral = fraxLend.balanceOf(address(this)) - initialBalance;

        if (computedCollateral < agreement.collaterals[0].amount) revert InsufficientAmountOut();
        agreement.collaterals[0].amount = computedCollateral;
    }

    function _close(uint256, /*tokenID*/ Agreement memory agreement, bytes memory data) internal override {
        uint256 minimumAmountOut = abi.decode(data, (uint256));

        uint256 amountIn = fraxLend.redeem(agreement.collaterals[0].amount, address(this), address(this));
        if (amountIn < minimumAmountOut) revert InsufficientAmountOut();
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory toRedeem = new uint256[](1);
        toRedeem[0] = fraxLend.convertToAssets(agreement.collaterals[0].amount);

        return toRedeem;
    }
}
