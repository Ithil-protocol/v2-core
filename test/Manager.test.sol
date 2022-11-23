// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IManager } from "../src/interfaces/IManager.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { Manager } from "../src/Manager.sol";

contract MockService {
    IManager internal immutable manager;
    address internal immutable token;

    constructor(IManager _manager, address _token) {
        manager = _manager;
        token = _token;
    }

    function pull(uint256 amount) external {
        manager.borrow(token, amount);
    }

    function push(uint256 debt, uint256 amount) external {
        manager.repay(token, debt, amount);
    }
}

contract ManagerTest is PRBTest, StdCheats {
    ERC20PresetMinterPauser internal immutable token;
    Manager internal immutable manager;
    MockService internal immutable service;
    address internal vault;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        manager = new Manager();
        service = MockService(address(manager));
    }

    function setUp() public {
        vault = manager.create(address(token));
        token.approve(vault, type(uint256).max);
        manager.addService(address(service));
    }

    function testCreateVaultSuccessful() public {
        assertTrue(vault != address(0));
        assertTrue(vault == manager.vaults(address(token)));
    }

    function testCreateVaultTwiceReverts() public {
        vm.expectRevert();
        manager.create(address(token));
    }

    function testBorrow() public {
        uint256 amount = 1e18;
        token.mint(address(this), amount);
        IVault(vault).deposit(amount, address(this));
        service.pull(amount);
    }
}
