// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "../interfaces/IVault.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract CreditService is Service {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    error InvalidInput();

    function open(Order calldata order) public virtual override unlocked {
        Agreement memory agreement = order.agreement;
        // Transfers deposit the loan to the relevant vault
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            address vaultAddress = manager.vaults(agreement.loans[index].token);
            if (
                agreement.collaterals[index].itemType != ItemType.ERC20 ||
                agreement.collaterals[index].token != vaultAddress
            ) revert InvalidInput();
            // Transfer tokens to this
            IERC20(agreement.loans[index].token).safeTransferFrom(
                msg.sender,
                address(this),
                agreement.loans[index].amount
            );

            // Deposit toekns to the relevant vault
            if (
                IERC20(agreement.loans[index].token).allowance(address(this), vaultAddress) <
                agreement.loans[index].amount
            ) IERC20(agreement.loans[index].token).approve(vaultAddress, type(uint256).max);
            uint256 shares = IVault(vaultAddress).deposit(agreement.loans[index].amount, address(this));

            // Register obtained shares and update exposures
            agreement.collaterals[index].amount = shares;
            exposures[agreement.loans[index].token] += shares;
        }
        Service.open(order);
    }

    function close(uint256 tokenID, bytes calldata data) public virtual override {
        if (ownerOf(tokenID) != msg.sender) revert RestrictedToOwner();

        Service.close(tokenID, data);

        Agreement memory agreement = agreements[tokenID];
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            exposures[agreement.loans[index].token] = exposures[agreement.loans[index].token].positiveSub(
                agreement.collaterals[index].amount
            );
        }
    }

    function mintShares(address token, uint256 maxAmountIn) external returns (uint256) {
        uint256 sharesToMint = _canMint(token);
        uint256 sharesMinted;
        if (sharesToMint > 0) {
            sharesMinted = manager.directMint(token, address(this), sharesToMint, exposures[token], maxAmountIn);
            exposures[token] += sharesMinted;
        }
        return sharesMinted;
    }

    function burnShares(address token, uint256 maxAmountIn) external returns (uint256) {
        uint256 sharesToBurn = _canBurn(token);
        uint256 sharesBurnt;
        if (sharesToBurn > 0) {
            sharesBurnt = manager.directBurn(token, address(this), sharesToBurn, maxAmountIn);
            exposures[token] = exposures[token].positiveSub(sharesBurnt);
        }
        return sharesBurnt;
    }

    function _canMint(address token) internal virtual returns (uint256) {}

    function _canBurn(address token) internal virtual returns (uint256) {}
}
