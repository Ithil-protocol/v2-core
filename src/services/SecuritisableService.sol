// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { DebitService } from "./DebitService.sol";

abstract contract SecuritisableService is DebitService {
    event LenderWasChanged(uint256 indexed id, address indexed newLender);

    /*
    function purchaseCredit(uint256 id, address purchaser) external {
        assert(_exists(id));

        // repay debt and assign
        // repay already has the repayer parameter: no need to do a double transfer
        // Purchaser must previously approve the Vault to spend its tokens
        uint256 toPay = price(id);
        manager.repay(agreements[id].owed.token, toPay, agreements[id].owed.amount, purchaser);
        agreements[id].lender = purchaser;

        emit LenderWasChanged(id, purchaser);
    }

    function price(uint256 id) public view returns (uint256) {
        uint256 fees = calculateFees(id);
        BaseAgreement memory agreement = agreements[id];

        // Risk spread is annihilated when purchasing, thus we discount fees wrt risk spread
        return
            agreement.owed.amount +
            fees.safeMulDiv(
                agreements[id].interestRate - riskSpread[agreement.owed.token],
                agreements[id].interestRate
            );
    }
    */
}
