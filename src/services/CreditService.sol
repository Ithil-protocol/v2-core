// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "../interfaces/IVault.sol";
import { Service } from "./Service.sol";

abstract contract CreditService is Service {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public minLoan;

    event MinLoanWasUpdated(address indexed token, uint256 amount);

    error LoanBelowMinimum();
    error InvalidInput();

    function setMinLoan(address token, uint256 amount) external onlyGuardian {
        if (amount == 0) revert InvalidParams();
        if (token == address(0)) revert InvalidParams();
        minLoan[token] = amount;

        emit MinLoanWasUpdated(token, amount);
    }

    function open(Order calldata order) public virtual override unlocked {
        Agreement memory agreement = order.agreement;
        if (agreement.loans[0].amount < minLoan[agreement.loans[0].token]) revert LoanBelowMinimum();
        // Transfers deposit the loan to the relevant vault
        // every token corresponds to a collateral token (the vault's address)
        // therefore, the length of the collateral array must be at least the length of the loan array
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            address vaultAddress = manager.vaults(agreement.loans[index].token);
            if (
                vaultAddress == address(0) ||
                agreement.collaterals[index].itemType != ItemType.ERC20 ||
                agreement.collaterals[index].token != vaultAddress
            ) revert InvalidInput();
            // Transfer tokens to this
            IERC20(agreement.loans[index].token).safeTransferFrom(
                msg.sender,
                address(this),
                agreement.loans[index].amount
            );
        }

        Service.open(order);
    }

    function close(uint256 tokenID, bytes calldata data) public virtual override returns (uint256[] memory) {
        Agreement memory agreement = agreements[tokenID];
        address owner = ownerOf(tokenID);
        if (owner != msg.sender && agreement.createdAt + deadline > block.timestamp) revert RestrictedToOwner();
        Service.close(tokenID, data);
        // Due to the wide variety of cases we can consider for a credit service,
        // the redeem mechanism is left to the particular service implementation
    }

    // dueAmount must be implemented otherwise the credit service is worthless
    function dueAmount(Agreement memory agreement, bytes memory data) public view virtual returns (uint256);
}
