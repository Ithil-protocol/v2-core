// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPool } from "../../interfaces/external/aave/IPool.sol";
import { IAToken } from "../../interfaces/external/aave/IAToken.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { Service } from "../Service.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { console2 } from "forge-std/console2.sol";

/// @title    AaveService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking on any Aave markets
contract AaveService is SecuritisableService {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    IPool internal immutable aave;
    uint256 public totalAllowance;

    error IncorrectObtainedToken();
    error InsufficientAmountOut();
    error AgreementAmountsMismatch();

    constructor(address _manager, address _aave) Service("AaveService", "AAVE-SERVICE", _manager) {
        aave = IPool(_aave);
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        IAToken aToken = IAToken(agreement.collaterals[0].token);
        if (aToken.UNDERLYING_ASSET_ADDRESS() != agreement.loans[0].token) revert IncorrectObtainedToken();
        if (agreement.collaterals[0].amount != agreement.loans[0].amount + agreement.loans[0].margin)
            revert AgreementAmountsMismatch();

        totalAllowance = totalAllowance.safeAdd(agreement.collaterals[0].amount);
        IERC20(agreement.loans[0].token).approve(address(aave), agreement.loans[0].amount + agreement.loans[0].margin);
        aave.deposit(agreement.loans[0].token, agreement.loans[0].amount + agreement.loans[0].margin, address(this), 0);
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        uint256 minimumAmountOut = abi.decode(data, (uint256));
        uint256 toRedeem = IERC20(agreement.collaterals[0].token).balanceOf(address(this)).safeMulDiv(
            agreement.collaterals[0].amount,
            totalAllowance
        );
        totalAllowance = totalAllowance.positiveSub(agreement.collaterals[0].amount);
        uint256 amountIn = aave.withdraw(agreement.loans[0].token, toRedeem, address(this));
        if (amountIn < minimumAmountOut) revert InsufficientAmountOut();
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        uint256[] memory fees = new uint256[](1);
        uint256[] memory toRedeem = new uint256[](1);
        toRedeem[0] = IERC20(agreement.collaterals[0].token).balanceOf(address(this)).safeMulDiv(
            agreement.collaterals[0].amount,
            totalAllowance
        );
        return (toRedeem, fees);
    }
}
