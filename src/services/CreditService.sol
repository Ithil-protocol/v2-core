// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CreditService is Service {
    constructor(string memory _name, string memory _symbol, address _manager, address _interestRateModel)
        Service(_name, _symbol, _manager, _interestRateModel)
    {}
}
