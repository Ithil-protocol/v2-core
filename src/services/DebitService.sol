// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";

contract DebitService is Service {
    struct Agreement {
        Item[] owed;
        Item[] obtained;
        address lender;
        uint256 interestRate;
        uint256 createdAt;
    }
    mapping(uint256 => Agreement) public agreements;
}
