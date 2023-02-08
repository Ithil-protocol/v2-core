// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract WhitelistedService is Service {
    mapping(address => bool) public whitelisted;
    bool public enabled;

    event WhitelistAccessFlagWasToggled();
    event WhitelistStatusWasChanged(address indexed user, bool status);
    error UserIsNotWhitelisted();

    constructor() {
        enabled = true;
    }

    function toggleWhitelistFlag() external onlyOwner {
        enabled = !enabled;

        emit WhitelistAccessFlagWasToggled();
    }

    function addToWhitelist(address addr) external onlyOwner {
        whitelisted[addr] = true;

        emit WhitelistStatusWasChanged(addr, true);
    }

    function removeFromWhitelist(address addr) external onlyOwner {
        delete whitelisted[addr];

        emit WhitelistStatusWasChanged(addr, false);
    }

    function _beforeOpening(Agreement memory agreement, bytes calldata data) internal override {
        if (enabled && !whitelisted[msg.sender]) revert UserIsNotWhitelisted();
    }
}
