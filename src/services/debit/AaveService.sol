// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPool } from "../../interfaces/external/aave/IPool.sol";
import { IAToken } from "../../interfaces/external/aave/IAToken.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    AaveService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking on any Aave markets
contract AaveService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    IPool public immutable aave;
    mapping(address => uint256) public totalAllowance;

    error IncorrectObtainedToken();
    error InsufficientAmountOut();
    error ZeroCollateral();
    error ImpossibleToQuote();

    constructor(
        address _manager,
        address _aave,
        uint256 _deadline
    ) Service("AaveService", "AAVE-SERVICE", _manager, _deadline) {
        aave = IPool(_aave);
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override onlyWhitelisted {
        IAToken aToken = IAToken(agreement.collaterals[0].token);
        if (aToken.UNDERLYING_ASSET_ADDRESS() != agreement.loans[0].token) revert IncorrectObtainedToken();
        // The following is necessary, otherwise Aave could throw an INVALID_AMOUNT error when withdrawing
        // thus making the position impossible to close
        if (agreement.collaterals[0].amount == 0) revert ZeroCollateral();

        uint256 initialBalance = aToken.balanceOf(address(this));
        IERC20(agreement.loans[0].token).approve(address(aave), agreement.loans[0].amount + agreement.loans[0].margin);

        aave.supply(agreement.loans[0].token, agreement.loans[0].amount + agreement.loans[0].margin, address(this), 0);

        uint256 computedCollateral = aToken.balanceOf(address(this)) - initialBalance;
        // This check is here to protect the msg.sender from slippage, therefore reentrancy is not an issue
        if (computedCollateral < agreement.collaterals[0].amount) revert InsufficientAmountOut();
        agreement.collaterals[0].amount = computedCollateral;
        // Due to the above check, totalAllowance is positive if there is at least one open agreement
        totalAllowance[agreement.collaterals[0].token] =
            totalAllowance[agreement.collaterals[0].token] +
            computedCollateral;
    }

    function _close(uint256, /*tokenID*/ Agreement memory agreement, bytes memory data) internal override {
        uint256 minimumAmountOut = abi.decode(data, (uint256));
        // Recall totalAllowance > 0 if there is at least one open agreement
        uint256 toRedeem = (IAToken(agreement.collaterals[0].token).balanceOf(address(this)) *
            agreement.collaterals[0].amount) / totalAllowance[agreement.collaterals[0].token];
        totalAllowance[agreement.collaterals[0].token] = totalAllowance[agreement.collaterals[0].token] >
            agreement.collaterals[0].amount
            ? totalAllowance[agreement.collaterals[0].token] - agreement.collaterals[0].amount
            : 0;
        uint256 amountIn = aave.withdraw(agreement.loans[0].token, toRedeem, address(this));
        // This check is here to protect the msg.sender from slippage, therefore reentrancy is not an issue
        if (amountIn < minimumAmountOut) revert InsufficientAmountOut();
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory toRedeem = new uint256[](1);
        // This reverts if there are no open agreements, which is expected since it would be impossible to quote
        if (totalAllowance[agreement.collaterals[0].token] == 0) revert ImpossibleToQuote();
        toRedeem[0] =
            (IAToken(agreement.collaterals[0].token).balanceOf(address(this)) * agreement.collaterals[0].amount) /
            totalAllowance[agreement.collaterals[0].token];
        return toRedeem;
    }
}
