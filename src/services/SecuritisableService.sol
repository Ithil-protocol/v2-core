// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.17;

import { Service } from "./Service.sol";

abstract contract SecuritisableService is Service {
    event LenderWasChanged(uint256 indexed id, address indexed newLender);

    function purchaseCredit(uint256 id, address purchaser) external {
        assert(_exists(id));

        // TODO repay debt

        lender[id] = purchaser;

        emit LenderWasChanged(id, purchaser);
    }
}
