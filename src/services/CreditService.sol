// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CreditService is Service {
    // No need of lender or borrower: one side is always owner(), other is always the Vault(s)
    struct CreditAgreement {
        ERC20[] owed;
        Item[] obtained;
        uint256[] entitlements;
        uint256 createdAt;
    }

    uint256 public reward;
    mapping(uint256 => CreditAgreement) public agreements;

    constructor(string memory _name, string memory _symbol, address _manager, uint256 _reward)
        Service(_name, _symbol, _manager)
    {
        reward = _reward;
    }

    function setReward(uint256 _reward) external onlyOwner {
        reward = _reward;
    }
}
