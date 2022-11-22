// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Vault } from "../src/Vault.sol";
import { Router } from "../src/Router.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// https://book.getfoundry.sh/forge/writing-tests
contract RouterTest is PRBTest, StdCheats {
    Router internal immutable router;
    ERC20PresetMinterPauser internal immutable token;
    address internal vault;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        router = new Router(address(0));
    }

    function setUp() public {
        token.mint(address(this), type(uint128).max);
        vault = router.create(address(token));
    }

    function testCreateVaultSuccessful() public {
        assertTrue(vault != address(0));
        assertTrue(vault == router.vaults(address(token)));
    }

    function testCreateVaultTwiceReverts() public {
        vm.expectRevert();
        router.create(address(token));
    }

    function testDeposit() public {
        token.approve(address(router), type(uint256).max);
        router.deposit(address(token), address(this), 1000, 1);
    }
}
