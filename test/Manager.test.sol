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
import { GeneralMath } from "../src/libraries/GeneralMath.sol";

contract MockService {
    IManager internal immutable manager;
    address internal immutable token;

    constructor(IManager _manager, address _token) {
        manager = _manager;
        token = _token;

        IERC20(token).approve(manager.vaults(token), type(uint256).max);
    }

    function pull(uint256 amount) external {
        manager.borrow(token, amount);
    }

    function push(uint256 amount, uint256 debt) external {
        manager.repay(token, amount, debt);
    }
}

contract ManagerTest is PRBTest, StdCheats {
    using GeneralMath for uint256;
    using GeneralMath for int256;

    ERC20PresetMinterPauser internal immutable token;
    Manager internal immutable manager;
    MockService internal immutable service;
    IVault internal immutable vault;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        manager = new Manager();
        vault = IVault(manager.create(address(token)));
        service = new MockService(manager, address(token));
        manager.addService(address(service));
    }

    function setUp() public {
        token.mint(address(this), type(uint256).max);
        token.approve(address(vault), type(uint256).max);
    }

    function _depositAndBorrow(uint256 amount) internal {
        vault.deposit(amount, address(this));
        service.pull(amount);
    }

    function _repayWithProfit(uint256 amount, uint256 generatedFees) internal {
        token.transfer(address(service), generatedFees);
        service.push(amount + generatedFees, amount);
    }

    function _repayWithLoss(uint256 amount, uint256 loss) internal {
        service.push(amount - loss, amount);
    }

    function testCreateVaultSuccessful() public {
        assertTrue(address(vault) != address(0));
        assertTrue(address(vault) == manager.vaults(address(token)));
    }

    function testCreateVaultTwiceReverts() public {
        vm.expectRevert();
        manager.create(address(token));
    }

    function testBorrow(uint256 amount) public {
        vm.assume(amount > 0);
        uint256 balanceBefore = token.balanceOf(address(this));

        vault.deposit(amount, address(this));
        uint256 change = balanceBefore - token.balanceOf(address(this));
        assertTrue(change == amount);

        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialTotalAssets = vault.totalAssets();

        service.pull(amount - 1);
        // Net loans increased
        assertTrue(vault.netLoans() == amount - 1);
        // Vault balance decreased
        assertTrue(initialVaultBalance - token.balanceOf(address(vault)) == amount - 1);
        // Vault assets stay constant
        assertTrue(vault.totalAssets() == initialTotalAssets);
    }

    function testRepayWithProfit(uint256 amount, int256 fees) public {
        vm.assume(fees > 0 && amount > 0 && amount < type(uint256).max - uint256(fees));

        vault.deposit(amount, address(this));
        service.pull(amount - 1);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialDebt = vault.netLoans();

        _repayWithProfit(amount - 1, uint256(fees));

        // Net loans decreased
        assertTrue(vault.netLoans() == initialDebt.positiveSub(amount - 1));
        // Current profits increased
        assertTrue(vault.currentProfits() == fees);
        // Vault assets stay constant
        assertTrue(vault.totalAssets() == initialTotalAssets);
    }

    function testFeesUnlockTime(uint256 amount, int256 fees, uint256 timePast) public {
        vm.assume(fees > 0 && amount > 0 && timePast < 1e9 && amount < type(uint256).max - uint256(fees));

        vault.deposit(amount, address(this));
        service.pull(amount - 1);
        _repayWithProfit(amount - 1, uint256(fees));

        uint256 unlockTime = vault.feeUnlockTime();
        int256 latestRepay = int256(vault.latestRepay());

        uint256 nextTimestamp = block.timestamp + timePast;
        vm.warp(nextTimestamp);

        int256 expectedLocked = fees.safeMulDiv(
            int256(unlockTime.positiveSub(int256(nextTimestamp) - latestRepay)),
            int256(unlockTime)
        );
        assertTrue(vault.totalAssets() == token.balanceOf(address(vault)).positiveSub(expectedLocked));
    }

    function testRepayWithLossCoverableByFees() public {
        uint256 amount = 100e18;
        uint256 fees = 1e18;
        uint256 loss = 5e17;
        // This generates fees which are not yet unlocked
        vault.deposit(amount, address(this));
        service.pull(amount - 1);
        _repayWithProfit(amount - 1, fees);

        int256 initialProfits = vault.currentProfits();
        // Make a bad repay
        _depositAndBorrow(amount);
        _repayWithLoss(amount, loss);

        // Current profits are correctly updated
        assertTrue(vault.currentProfits() == initialProfits - int256(loss));
    }

    function testGenerateFeesWithNoLoans(uint256 amount) public {
        vm.assume(amount > 0);
        vault.deposit(amount, address(this));

        // Everything is free liquidity
        uint256 initialFreeLiquidity = vault.freeLiquidity();
        assertTrue(initialFreeLiquidity == amount);
        uint256 initialVaultAssets = vault.totalAssets();

        service.pull(amount - 1);
        _repayWithProfit(amount - 1, 0);

        // Assets stay constant (fees still locked)
        assertTrue(vault.totalAssets() == initialVaultAssets);
        // Free liquidity is constant
        assertTrue(vault.freeLiquidity() == initialFreeLiquidity);
        // Check there is no dust
        assertTrue(vault.netLoans() == 0);
        assertTrue(vault.currentProfits() == 0);
        // Latest repay is time
        assertTrue(vault.latestRepay() == block.timestamp);
    }
}
