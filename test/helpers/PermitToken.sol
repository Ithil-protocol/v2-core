// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract PermitToken is ERC20PresetMinterPauser, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20PresetMinterPauser(name, symbol) ERC20Permit(symbol) {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20PresetMinterPauser) {
        ERC20PresetMinterPauser._beforeTokenTransfer(from, to, amount);
    }
}
