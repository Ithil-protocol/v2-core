// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Router } from "../src/Router.sol";
import { Vault } from "../src/Vault.sol";

contract RouterTest is PRBTest, StdCheats {
    Router internal immutable router;
    ERC20PresetMinterPauser internal immutable token;
    Vault internal immutable vault;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        router = new Router(address(0));
        vault = new Vault(IERC20Metadata(address(token)));
    }

    function setUp() public {
        token.mint(address(this), type(uint256).max);
        token.approve(address(router), type(uint256).max);
        router.approve(token, address(vault), type(uint256).max);
    }

    function testDeposit(uint256 amount) public {
        uint256 shares = vault.previewDeposit(amount);
        uint256 deposited = router.deposit(vault, address(this), amount, shares);
        assertTrue(vault.previewDeposit(amount) == deposited);
    }

    function testSlippageOnDeposit(uint256 amount) public {
        uint256 shares = vault.previewDeposit(amount);

        vm.expectRevert();
        router.deposit(vault, address(this), amount, shares + 1);
    }

    /*function testWithdraw(uint256 amount) public {
        vm.assume(amount > 1);

        uint256 shares = vault.previewDeposit(amount);
        router.deposit(vault, address(this), amount, shares);
        shares = vault.previewWithdraw(amount);
        uint256 withdrawed = router.withdraw(vault, address(this), amount-1, shares);
        assertTrue(vault.previewWithdraw(amount) == withdrawed);
    }*/
}
