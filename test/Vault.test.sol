// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Vault } from "../src/Vault.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// @dev Run Forge with `-vvvv` to see console logs.
/// https://book.getfoundry.sh/forge/writing-tests
contract VaultTest is PRBTest, StdCheats {
    Vault internal immutable vault;
    ERC20PresetMinterPauser internal immutable token;
    uint256 internal constant amount = 1000;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        vault = new Vault(IERC20Metadata(address(token)));
    }

    function setUp() public {
        token.mint(address(this), type(uint128).max);
        token.approve(address(vault), type(uint256).max);
    }

    function testBase() public {
        assertTrue(vault.decimals() == token.decimals());
    }

    function testDeposit() public {
        uint256 balanceBefore = token.balanceOf(address(this));
        vault.deposit(amount, address(this));
        assertTrue(vault.totalAssets() == amount);
        uint256 change = balanceBefore - token.balanceOf(address(this));
        assertTrue(change == amount);
        assertTrue(vault.balanceOf(address(this)) == amount);
    }

    function testWithdraw() public {
        uint256 balanceBefore = token.balanceOf(address(this));

        vault.withdraw(amount-1, address(this), address(this));
        assertTrue(vault.totalAssets() == 1);
        uint256 change = balanceBefore - token.balanceOf(address(this));
        assertTrue(change == amount-1);
    }
}
