// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { DebitService } from "./DebitService.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract SecuritisableService is DebitService {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    event LenderWasUpdated(uint256 indexed id, address indexed newLender);

    /// @dev The lender is initialized only after purchase
    /// In this way, exiting can check lender to trigger a repay or transfer
    mapping(uint256 => address) public lenders;

    function purchaseCredit(uint256 id, address purchaser) external {
        assert(_exists(id));

        Agreement memory agreement = agreements[id];
        Loan[] memory loans = agreement.loans;
        (uint256[] memory values, uint256[] memory fees) = quote(agreement);

        for (uint256 index = 0; index < values.length; index++) {
            exposures[agreement.loans[index].token] = exposures[agreement.loans[index].token].positiveSub(
                agreement.loans[index].amount
            );
            uint256 price = _priceDebit(loans[index].amount, fees[index], loans[index].interestAndSpread);
            /// @dev Repay debt
            /// repay already has the repayer parameter: no need to do a double transfer
            /// Purchaser must previously approve the Vault to spend its tokens
            manager.repay(loans[index].token, price, loans[index].amount, purchaser);
        }

        lenders[id] = purchaser;

        emit LenderWasUpdated(id, purchaser);
    }

    function close(uint256 tokenID, bytes calldata data) public override {
        super.close(tokenID, data);

        Agreement memory agreement = agreements[tokenID];
        // In this case the debit has been purchased
        if (lenders[tokenID] != address(0)) {
            // Debit was purchased: the payoff should be transferred to the new lender
            for (uint256 index = 0; index < agreement.loans.length; index++) {
                IERC20(agreement.loans[index].token).safeTransfer(
                    lenders[tokenID],
                    _computeDuePayment(agreement, data)
                );
            }
        }
    }

    function _priceDebit(uint256 amount, uint256 fees, uint256 interestAndSpread) internal virtual returns (uint256) {
        /// @dev Risk spread is annihilated when purchasing, thus we discount fees wrt risk spread
        (uint256 interestRate, uint256 riskSpread) = interestAndSpread.unpackUint();
        return amount + fees.safeMulDiv(riskSpread, interestRate + riskSpread);
    }
}
