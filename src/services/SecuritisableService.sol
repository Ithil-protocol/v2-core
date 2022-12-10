// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { DebitService } from "./DebitService.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract SecuritisableService is DebitService {
    using GeneralMath for uint256;

    event LenderWasChanged(uint256 indexed id, address indexed newLender);

    mapping(uint256 => bool) public wasPurchased;

    function purchaseCredit(uint256 id, address purchaser) external {
        assert(_exists(id));

        (uint256[] memory values, uint256[] memory fees) = quote(id);
        Loan[] memory loans = agreements[id].loans;

        for (uint256 index = 0; index < values.length; index++) {
            // Risk spread is annihilated when purchasing, thus we discount fees wrt risk spread
            (uint256 interestRate, uint256 riskSpread) = loans[index].interestAndSpread.unpackUint();
            uint256 price = loans[index].amount + fees[index].safeMulDiv(interestRate - riskSpread, interestRate);
            // repay debt
            // repay already has the repayer parameter: no need to do a double transfer
            // Purchaser must previously approve the Vault to spend its tokens
            manager.repay(loans[index].token, price, loans[index].amount, purchaser);
        }

        // reassign and mark as purchased (develop such that exiting will not repay the vault)
        agreements[id].lender = purchaser;
        wasPurchased[id] = true;

        emit LenderWasChanged(id, purchaser);
    }
}
