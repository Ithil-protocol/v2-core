// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title    ITHIL token contract
/// @author   Ithil
contract Ithil is ERC20, ERC20Permit {
    constructor(address governance) ERC20("Ithil", "ITHIL") ERC20Permit("Ithil") {
        _mint(governance, 1e8 * 10 ** decimals());
    }
}
