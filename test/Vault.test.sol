// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Vault } from "../src/Vault.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract VaultTest is PRBTest, StdCheats {
    Vault internal immutable vault;
    ERC20PresetMinterPauser internal immutable token;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        vault = new Vault(IERC20Metadata(address(token)));
    }

    function setUp() public {
        token.mint(address(this), type(uint128).max);
        token.approve(address(vault), type(uint256).max);
    }

    /// @dev Run Forge with `-vvvv` to see console logs.
    function testExample() public {
        uint256 amount = 1000;
        
        assertTrue(vault.decimals() == token.decimals());
        vault.deposit(amount, address(this));
        assertTrue(vault.totalAssets() == amount);
    }
}
