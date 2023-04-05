// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title    VeIthil (vested ITHIL) token contract
/// @author   Ithil
contract VeIthil is ERC20, ERC20Permit, ERC20Votes {
    error NotTransferrable();

    constructor() ERC20("veIthil", "veITHIL") ERC20Permit("veIthil") {
        _mint(msg.sender, 1e8 * 10**decimals());
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        if(from != address(0) && to != address(0)) revert NotTransferrable();
        ERC20Votes._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        ERC20Votes._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        ERC20Votes._burn(account, amount);
    }
}
