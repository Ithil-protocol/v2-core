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
        vault.deposit(1, address(this));
    }

    function _borrow(uint256 amount) internal {
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
        vm.assume(amount < type(uint256).max);

        uint256 balanceBefore = token.balanceOf(address(this));

        vault.deposit(amount, address(this));
        uint256 change = balanceBefore - token.balanceOf(address(this));
        assertTrue(change == amount);

        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialTotalAssets = vault.totalAssets();

        service.pull(amount);
        // Net loans increased
        assertTrue(vault.netLoans() == amount);
        // Vault balance decreased
        assertTrue(initialVaultBalance - token.balanceOf(address(vault)) == amount);
        // Vault assets stay constant
        assertTrue(vault.totalAssets() == initialTotalAssets);
    }

    function testRepayWithProfit() public {
        //vm.assume(amount > 0 && fees > 0 && amount <= type(uint256).max - fees -1);

        uint256 amount = 100e18;
        uint256 fees = 1e18;

        _borrow(amount);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialDebt = vault.netLoans();

        _repayWithProfit(amount, fees);

        // Net loans decreased
        assertTrue(vault.netLoans() == initialDebt - amount);
        // Current profits increased
        assertTrue(vault.currentProfits() == int256((fees)));
        // Vault assets stay constant
        assertTrue(vault.totalAssets() == initialTotalAssets);
    }

    function testFeesUnlockTime() public {
        uint256 amount = 100e18;
        uint256 fees = 1e18;

        _borrow(amount);
        _repayWithProfit(amount, fees);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 unlockTime = vault.feeUnlockTime();
        uint256 latestRepay = vault.latestRepay();

        uint256 nextTimestamp = block.timestamp + unlockTime / 2;
        vm.warp(nextTimestamp);

        uint256 expectedUnlock = ((nextTimestamp - latestRepay) * fees) / unlockTime;

        assertTrue(vault.totalAssets() == initialTotalAssets + expectedUnlock);
    }

    function testRepayWithLossCoverableByFees() public {
        /*
        uint256 amount = 100e18;
        uint256 fees = 1e18;

        _borrow(amount);
        _repayWithProfit(amount, fees);

        uint256 unlockTime = vault.feeUnlockTime();
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialBalance = token.balanceOf(address(this));
        uint256 currentLoans = vault.netLoans();
        uint256 currentProfits = uint256(vault.currentProfits());
        uint256 latestRepay = vault.latestRepay();

        uint256 nextTimestamp = block.timestamp + unlockTime / 2;
        uint256 expectedUnlock = ((nextTimestamp - latestRepay) * fees) / unlockTime;
        uint256 expectedLockedProfits = currentProfits - expectedUnlock;

        // Repay half of the loans with a 10% loss
        uint256 debtToRepay = amount / 2;
        uint256 loss = expectedLockedProfits / 2;
        _repayWithLoss(debtToRepay, loss);

        // Net loans decreased
        assertTrue(vault.netLoans() == currentLoans - debtToRepay);
        // Investor2 balance decreased
        assertTrue(token.balanceOf(address(this)) == (initialBalance - debtToRepay - loss));
        // Vault balance increased
        assertTrue(token.balanceOf(address(vault)) == (initialVaultBalance + debtToRepay - loss));

        // Current profits decrease
        const blockNumBefore = await ethers.provider.getBlockNumber();
        const blockBefore = await ethers.provider.getBlock(blockNumBefore);
        const timestampBefore = BigNumber.from(blockBefore.timestamp);
        const unlockedProfits = timestampBefore.sub(latestRepay).mul(currentProfits).div(unlockTime);
        const lockedProfits = currentProfits.sub(unlockedProfits);
        expect(await vault.currentProfits()).to.equal(lockedProfits.sub(loss).sub(1)); // -1 for rounding errors
        */
    }

    function testGenerateFeesWithNoLoans(uint256 amount) public {
        vm.assume(amount < type(uint256).max);

        vault.deposit(amount, address(this));

        // Everything is free liquidity
        uint256 initialFreeLiquidity = vault.freeLiquidity();
        assertTrue(initialFreeLiquidity == amount + 1);
        uint256 initialVaultAssets = vault.totalAssets();

        service.pull(amount);
        _repayWithProfit(amount, 0);

        // Assets stay constant (fees still locked)
        assertTrue(vault.totalAssets() == initialVaultAssets);
        // Free liquidity is constant
        assertTrue(vault.freeLiquidity() == initialFreeLiquidity);
        // Check there is no dust
        assertTrue(vault.netLoans() == 0);
        // Current profits increased
        assertTrue(uint256(vault.currentProfits()) == 0);
        // Latest repay is time
        assertTrue(vault.latestRepay() == block.timestamp);
    }
}
