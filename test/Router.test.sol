// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Router } from "../src/Router.sol";
import { Vault } from "../src/Vault.sol";

contract ManagerTest is PRBTest, StdCheats {
    Router internal immutable router;
    ERC20PresetMinterPauser internal immutable token;
    Vault internal immutable vault;
    uint256 constant amount = 1000;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        router = new Router(address(0));
        vault = new Vault(IERC20Metadata(address(token)));
    }

    function setUp() public {
        token.mint(address(this), type(uint128).max);
        token.approve(address(router), type(uint256).max);
        router.selfApprove(token, address(vault), amount);
    }

    function testDeposit() public {
        uint256 deposited = router.deposit(vault, address(this), amount, 1);
        assertTrue(vault.previewDeposit(amount) == deposited);
    }

    function testSlippageOnDeposit() public {
        vm.expectRevert();
        router.deposit(vault, address(this), amount, amount + 1);
    }

    /*function testWithdraw() public {
        router.deposit(vault, address(this), amount, 1);
        uint256 withdrawed = router.withdraw(vault, address(this), amount, 1);
        assertTrue(vault.previewWithdraw(amount) == withdrawed);
    }*/
}
