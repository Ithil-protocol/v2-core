// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CreditService } from "../CreditService.sol";
import { IService } from "../../interfaces/IService.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { Service } from "../Service.sol";

/// @title    Fixed Yield contract
/// @author   Ithil
/// @notice   A service to provide liquidity at a fixed yield
/// @notice   Boosting is a particular case with yield = 0 (or in general lower than LPs' average)
/// @notice   By putting a positive yield and a finite deadline, we obtain classical bonds
/// @notice   In this implementation, fixed yield creditors are more guaranteed than vanilla LPs
contract FixedYieldService is CreditService {
    error SlippageExceeded();
    // The yield of this service, with 1e18 corresponding to 100% annually
    // Here 1 year is defined as to be 365 * 86400 seconds

    uint256 public immutable yield;

    constructor(
        address _manager,
        uint256 _yield,
        uint256 _deadline
    ) Service("Fixed Yield Service", "FIXED-YIELD-SERVICE", _manager, _deadline) {
        yield = _yield;
    }

    function _open(IService.Agreement memory agreement, bytes memory /*data*/) internal virtual override {
        address vaultAddress = manager.vaults(agreement.loans[0].token);
        if (IERC20(agreement.loans[0].token).allowance(address(this), vaultAddress) < agreement.loans[0].amount) {
            IERC20(agreement.loans[0].token).approve(vaultAddress, type(uint256).max);
        }
        // Deposit tokens to the relevant vault and register obtained amount
        uint256 shares = IVault(vaultAddress).deposit(agreement.loans[0].amount, address(this));
        // This check is here to protect the msg.sender from slippage, therefore reentrancy is not an issue
        if (shares < agreement.collaterals[0].amount) revert SlippageExceeded();
        agreement.collaterals[0].amount = shares;
    }

    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual override {
        // gas savings
        IVault vault = IVault(manager.vaults(agreement.loans[0].token));
        address owner = ownerOf(tokenID);

        uint256 minAmountOut = abi.decode(data, (uint256));

        // redeem mechanism: we first redeem everything and transfer proceedings here
        uint256 redeemed = vault.redeem(agreement.collaterals[0].amount, address(this), address(this));
        if (redeemed < minAmountOut) revert SlippageExceeded();
        uint256 toTransfer = dueAmount(agreement, data);

        if (toTransfer > redeemed) {
            // Since this service is senior, we need to pay the user even if redeemable is too low
            // To do this, we take liquidity from the vault and register the loss (no loan)
            uint256 freeLiquidity = vault.freeLiquidity() - 1;
            if (freeLiquidity > 0) {
                manager.borrow(
                    agreement.loans[0].token,
                    toTransfer - redeemed > freeLiquidity ? freeLiquidity : toTransfer - redeemed,
                    0,
                    owner
                );
            }
            toTransfer = redeemed;
        } else {
            // In the ideal case when the amount to transfer is less than the maximum redeemable
            // we generate a profit by repaying the Vault of the difference, thus creating a "boost"
            manager.repay(agreement.loans[0].token, redeemed - toTransfer, 0, address(this));
        }
        IERC20(agreement.loans[0].token).transfer(owner, toTransfer);
    }

    function dueAmount(
        IService.Agreement memory agreement,
        bytes memory /*data*/
    ) public view virtual override returns (uint256) {
        // loan * (1 + yield * time)
        return
            agreement.loans[0].amount +
            (((agreement.loans[0].amount * yield) / 1e18) * (block.timestamp - agreement.createdAt)) /
            (86400 * 365);
    }
}
