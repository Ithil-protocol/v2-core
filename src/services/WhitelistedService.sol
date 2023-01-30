// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract WhitelistedService is Service {
    mapping(address => bool) public whitelisted;
    event WhitelistStatusWasChanged(address indexed user, bool flag);
    error UserIsNotWhitelisted();

    function setWhitelistStatus(address addr, bool flag) external onlyOwner {
        whitelisted[addr] = flag;

        emit WhitelistStatusWasChanged(addr, flag);
    }

    function _beforeOpening(Agreement memory agreement, bytes calldata data) internal override {
        if (!whitelisted[msg.sender]) revert UserIsNotWhitelisted();
    }
}
