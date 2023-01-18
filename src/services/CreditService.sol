// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IVault } from "../interfaces/IVault.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract CreditService is Service {
    using GeneralMath for uint256;

    error Input_Badly_Composed();

    function close(uint256 tokenID, bytes calldata data) public override {
        if (ownerOf(tokenID) != msg.sender) revert RestrictedToOwner();

        super.close(tokenID, data);
    }

    function _beforeOpening(Agreement memory agreement, bytes calldata data) internal virtual override {
        // Transfers deposit the loan to the relevant vault
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            address vaultAddress = manager.vaults(agreement.loans[index].token);
            if (
                agreement.collaterals[index].itemType != ItemType.ERC20 ||
                agreement.collaterals[index].token != vaultAddress
            ) revert Input_Badly_Composed();
            uint256 shares = IVault(vaultAddress).deposit(agreement.loans[index].amount, address(this));
            agreement.collaterals[index].amount = shares;
            exposures[agreement.loans[index].token] += shares;
        }
    }

    function _afterClosing(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal virtual override {
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            exposures[agreement.loans[index].token] = exposures[agreement.loans[index].token].positiveSub(
                agreement.collaterals[index].amount
            );
        }
    }
}
