// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IService } from "../interfaces/IService.sol";

abstract contract Whitelisted is Ownable {
    mapping(address => bool) public whitelisted;
    bool public enabled;

    event WhitelistAccessFlagWasToggled();
    event WhitelistedStatusWasChanged(address indexed user, bool status);

    error UserIsNotWhitelisted();

    constructor() {
        enabled = true;
    }

    // This reverts if the msg.sender is not whitelisted and the enabled flag is true
    modifier onlyWhitelisted() {
        if (enabled && !whitelisted[msg.sender]) revert UserIsNotWhitelisted();
        _;
    }

    function toggleWhitelistFlag() external onlyOwner {
        enabled = !enabled;

        emit WhitelistAccessFlagWasToggled();
    }

    function addToWhitelist(address[] calldata users) external onlyOwner {
        uint256 length = users.length;
        for (uint256 i = 0; i < length; i++) {
            whitelisted[users[i]] = true;

            emit WhitelistedStatusWasChanged(users[i], true);
        }
    }

    function removeFromWhitelist(address[] calldata users) external onlyOwner {
        uint256 length = users.length;
        for (uint256 i = 0; i < length; i++) {
            delete whitelisted[users[i]];

            emit WhitelistedStatusWasChanged(users[i], false);
        }
    }
}
