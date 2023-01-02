// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault, Vault } from "../src/Vault.sol";
import { GeneralMath } from "../src/libraries/GeneralMath.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// @dev Run Forge with `-vvvv` to see console logs.
/// https://book.getfoundry.sh/forge/writing-tests

/// @dev Vault native state:
/// - Native:
/// address public immutable manager;
/// uint256 public immutable override creationTime;
/// uint256 public override feeUnlockTime;
/// uint256 public override netLoans;
/// uint256 public override latestRepay;
/// uint256 public override currentProfits;
/// uint256 public override currentLosses;

/// @dev Vault ERC4626 state
/// - Vault is ERC4626: totalSupply(), balanceOf(address(this)), balanceOf(msg.sender),
/// - balanceOf(owner), balanceOf(receiver) (deposit, withdraw, directMint, directBurn)

/// @dev Vault underlying ERC20 state
/// - ERC4626 -> constructor(IERC20 asset_): totalSupply(), balanceOf(address(this)), balanceOf(msg.sender),
/// - balanceOf(owner), balanceOf(receiver) (deposit, withdraw, directMint, directBurn)

contract VaultTest is PRBTest, StdCheats {
    using GeneralMath for uint256;
    using GeneralMath for int256;

    Vault internal immutable vault;
    ERC20PresetMinterPauser internal immutable token;
    ERC20PresetMinterPauser internal immutable spuriousToken;
    address internal immutable tokenSink;
    address internal immutable notOwner;
    address internal immutable anyAddress;
    address internal immutable depositor;
    address internal immutable receiver;
    address internal immutable borrower;
    address internal immutable repayer;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");
        vault = new Vault(IERC20Metadata(address(token)));
        tokenSink = address(uint160(uint(keccak256(abi.encodePacked("Sink")))));
        notOwner = address(uint160(uint(keccak256(abi.encodePacked("Not Owner")))));
        anyAddress = address(uint160(uint(keccak256(abi.encodePacked("Any Address")))));
        depositor = address(uint160(uint(keccak256(abi.encodePacked("Depositor")))));
        receiver = address(uint160(uint(keccak256(abi.encodePacked("Receiver")))));
        repayer = address(uint160(uint(keccak256(abi.encodePacked("Repayer")))));
        borrower = address(uint160(uint(keccak256(abi.encodePacked("Borrower")))));
        spuriousToken = new ERC20PresetMinterPauser("spurious", "SPURIOUS");
    }

    function setUp() public {
        token.mint(tokenSink, type(uint256).max);
        token.approve(address(vault), type(uint256).max);
    }

    function testBase() public {
        // Native state
        assertTrue(vault.manager() == address(this));
        assertTrue(vault.creationTime() == block.timestamp);
        assertTrue(vault.feeUnlockTime() == 21600);
        assertTrue(vault.latestRepay() == 0);
        assertTrue(vault.netLoans() == 0);
        assertTrue(vault.currentProfits() == 0);
        assertTrue(vault.currentLosses() == 0);

        // ERC4626 state
        assertTrue(vault.totalSupply() == 0);
        assertTrue(vault.balanceOf(address(this)) == 0);
        assertTrue(vault.balanceOf(msg.sender) == 0);
        assertTrue(keccak256(bytes(vault.name())) == keccak256(bytes("Ithil test")));
        assertTrue(keccak256(bytes(vault.symbol())) == keccak256(bytes("iTEST")));
        assertTrue(vault.asset() == address(token));
        assertTrue(vault.decimals() == token.decimals());

        // Underlying ERC20 state
        assertTrue(token.balanceOf(address(vault)) == 0);
        assertTrue(token.balanceOf(tokenSink) == type(uint256).max);
    }

    function testAccess(uint256 shares, uint256 assets, uint256 debt) public {
        vm.startPrank(notOwner);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.setFeeUnlockTime(1000);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.sweep(anyAddress, address(spuriousToken));
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.directMint(shares, anyAddress);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.directBurn(shares, anyAddress);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.borrow(assets, anyAddress);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Not_Owner()"))));
        vault.repay(assets, debt, anyAddress);
        vm.stopPrank();
    }

    function _nativeStateCheck(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses
    ) internal {
        assertTrue(vault.feeUnlockTime() == feeUnlockTime);
        assertTrue(vault.totalSupply() == totalSupply);
        assertTrue(token.balanceOf(address(vault)) == balanceOf);
        assertTrue(vault.netLoans() == netLoans);
        assertTrue(vault.latestRepay() == latestRepay);
        assertTrue(vault.currentProfits() == currentProfits);
        assertTrue(vault.currentLosses() == currentLosses);
    }

    function _setupArbitraryState(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses
    ) internal {
        // Set fee unlock time
        vm.assume(feeUnlockTime > 30 && feeUnlockTime < 7 days);
        vault.setFeeUnlockTime(feeUnlockTime);

        // Set totalSupply by depositing
        vm.prank(tokenSink);
        token.transfer(depositor, totalSupply);
        vm.prank(depositor);
        token.approve(address(vault), totalSupply);
        vault.deposit(totalSupply, receiver, depositor);

        // Set latestRepay
        vm.warp(latestRepay);
        vault.repay(0, 0, repayer);

        // Set currentProfits (assume this otherwise there are no tokens available)
        vm.assume(currentProfits <= token.totalSupply() - totalSupply);
        vm.prank(tokenSink);
        token.transfer(repayer, currentProfits);
        vm.prank(repayer);
        token.approve(address(vault), currentProfits);
        vault.repay(currentProfits, 0, repayer);

        // Set currentLosses
        vm.assume(currentLosses < vault.freeLiquidity());
        vault.borrow(currentLosses, borrower);
        vault.repay(0, currentLosses, repayer);

        // Set netLoans
        vm.assume(netLoans < vault.freeLiquidity());
        vault.borrow(netLoans, borrower);

        // Set balanceOf by adjusting
        vm.assume(balanceOf > 0); // Otherwise it fails due to unhealthy vault
        uint256 initialBalance = token.balanceOf(address(vault));
        // TODO: remove first assumption (the second is necessary because totalSupply is fixed)
        vm.assume(balanceOf > initialBalance && balanceOf - initialBalance <= token.balanceOf(tokenSink));
        vm.prank(tokenSink);
        token.transfer(address(vault), balanceOf - initialBalance);

        _nativeStateCheck(feeUnlockTime, totalSupply, balanceOf, netLoans, latestRepay, currentProfits, currentLosses);
    }

    function testFeeUnlockTime(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 feeUnlockTimeSet
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
        if (feeUnlockTimeSet < 30 || feeUnlockTimeSet > 7 days) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("Fee_Unlock_Out_Of_Range()"))));
            vault.setFeeUnlockTime(feeUnlockTimeSet);
        } else {
            vault.setFeeUnlockTime(feeUnlockTimeSet);
            assertTrue(vault.feeUnlockTime() == feeUnlockTimeSet);
            feeUnlockTime = feeUnlockTimeSet;
        }
        // Recheck the remaining state is unchanged (except feeUnlockTime but it's already reassigned)
        _nativeStateCheck(feeUnlockTime, totalSupply, balanceOf, netLoans, latestRepay, currentProfits, currentLosses);
    }

    function testSweep(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 spuriousAmount
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        spuriousToken.mint(address(vault), spuriousAmount);
        assertTrue(spuriousToken.balanceOf(address(vault)) == spuriousAmount);

        vault.sweep(anyAddress, address(spuriousToken));
        assertTrue(spuriousToken.balanceOf(address(vault)) == 0);
        assertTrue(spuriousToken.balanceOf(anyAddress) == spuriousAmount);

        // Recheck the remaining state is unchanged (except feeUnlockTime)
        _nativeStateCheck(feeUnlockTime, totalSupply, balanceOf, netLoans, latestRepay, currentProfits, currentLosses);
    }

    function testDeposit(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 deposited
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        uint256 initialReceiverShares = vault.balanceOf(receiver);
        uint256 initialDepositorShares = vault.balanceOf(depositor);
        uint256 initialDepositorAssets = token.balanceOf(depositor);
        uint256 initialVaultAssets = token.balanceOf(address(vault));
        uint256 initialVaultTotalSupply = vault.totalSupply();

        // Necessary assumption because token totalSupply is fixed
        if (deposited > initialDepositorAssets) {
            vm.assume(deposited - initialDepositorAssets < token.balanceOf(tokenSink));
            vm.prank(tokenSink);
            token.transfer(depositor, deposited - initialDepositorAssets);
        }

        vm.startPrank(depositor);
        token.approve(address(vault), deposited);
        uint256 shares = vault.deposit(deposited, receiver, depositor);
        vm.stopPrank();

        // Specific addresses' state changes
        assertTrue(vault.balanceOf(address(receiver)) == initialReceiverShares + shares);
        assertTrue(vault.balanceOf(address(depositor)) == initialDepositorShares);

        // Vault state change
        _nativeStateCheck(
            feeUnlockTime,
            initialVaultTotalSupply + shares,
            initialVaultAssets + deposited,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testMint(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 minted
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        uint256 initialReceiverShares = vault.balanceOf(receiver);
        uint256 initialDepositorShares = vault.balanceOf(depositor);
        uint256 initialDepositorAssets = token.balanceOf(depositor);
        uint256 initialVaultAssets = token.balanceOf(address(vault));
        uint256 initialVaultTotalSupply = vault.totalSupply();

        // Necessary to avoid overflow
        if (vault.totalAssets() > 0 && vault.totalSupply() > 0)
            vm.assume(minted / vault.totalSupply() < (type(uint256).max / vault.totalAssets()));
        uint256 deposited = vault.previewMint(minted);

        // Necessary assumption because token totalSupply is fixed
        if (deposited > initialDepositorAssets) {
            vm.assume(deposited - initialDepositorAssets < token.balanceOf(tokenSink));
            vm.prank(tokenSink);
            token.transfer(depositor, deposited - initialDepositorAssets);
        }

        vm.startPrank(depositor);
        token.approve(address(vault), deposited);
        vault.mint(minted, receiver, depositor);
        vm.stopPrank();

        // Specific addresses' state changes
        assertTrue(vault.balanceOf(address(receiver)) == initialReceiverShares + minted);
        assertTrue(vault.balanceOf(address(depositor)) == initialDepositorShares);

        // Vault state change
        _nativeStateCheck(
            feeUnlockTime,
            initialVaultTotalSupply + minted,
            initialVaultAssets + deposited,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testWithdraw(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 withdrawn
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        // At this stage receiver has the entirety of the supply
        assertTrue(vault.balanceOf(receiver) == totalSupply);

        uint256 initialReceiverAssets = token.balanceOf(receiver);
        uint256 initialReceiverShares = vault.balanceOf(receiver);
        uint256 shares = 0;

        vm.startPrank(receiver);
        if (withdrawn >= vault.freeLiquidity()) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("Insufficient_Liquidity()"))));
            vault.withdraw(withdrawn, receiver, receiver);
            withdrawn = 0;
        }

        shares = vault.withdraw(withdrawn, receiver, receiver);
        assertTrue(vault.balanceOf(receiver) == initialReceiverShares - shares);
        assertTrue(token.balanceOf(receiver) == initialReceiverAssets + withdrawn);

        vm.stopPrank();

        // Vault state change
        _nativeStateCheck(
            feeUnlockTime,
            totalSupply - shares,
            balanceOf - withdrawn,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testRedeem(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 redeemed
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        // At this stage receiver has the entirety of the supply
        assertTrue(vault.balanceOf(receiver) == totalSupply);
        vm.assume(redeemed < totalSupply);

        uint256 initialReceiverAssets = token.balanceOf(receiver);
        uint256 initialReceiverShares = vault.balanceOf(receiver);
        uint256 withdrawn = vault.previewRedeem(redeemed);

        vm.startPrank(receiver);
        if (withdrawn >= vault.freeLiquidity()) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("Insufficient_Liquidity()"))));
            vault.redeem(redeemed, receiver, receiver);
            redeemed = 0;
            withdrawn = 0;
        }
        vault.redeem(redeemed, receiver, receiver);
        assertTrue(vault.balanceOf(receiver) == initialReceiverShares - redeemed);
        assertTrue(token.balanceOf(receiver) == initialReceiverAssets + withdrawn);

        vm.stopPrank();

        // Vault state change
        _nativeStateCheck(
            feeUnlockTime,
            totalSupply - redeemed,
            balanceOf - withdrawn,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testDirectMint(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 minted,
        uint256 newTimestamp
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        // 30 billion years and not going backwards in time
        vm.assume(newTimestamp <= 1e18 && newTimestamp >= latestRepay);
        vm.warp(newTimestamp);
        uint256 lockedProfits = currentProfits.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );
        uint256 lockedLosses = currentLosses.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );
        // Necessary to avoid overflow
        vm.assume(minted <= type(uint256).max - vault.totalSupply());
        if (vault.totalAssets() > 0 && vault.totalSupply() > 0)
            vm.assume(minted / vault.totalSupply() < (type(uint256).max / vault.totalAssets()));
        uint256 initialShares = vault.balanceOf(anyAddress);
        uint256 increasedAssets = vault.directMint(minted, anyAddress);
        assertTrue(vault.balanceOf(anyAddress) == initialShares + minted);

        _nativeStateCheck(
            feeUnlockTime,
            totalSupply + minted,
            balanceOf,
            netLoans,
            newTimestamp,
            lockedProfits,
            lockedLosses + increasedAssets
        );
    }

    function testDirectBurn(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 burned,
        uint256 newTimestamp
    ) public {
        // 30 billion years and not going backwards in time
        vm.assume(newTimestamp <= 1e18 && newTimestamp >= latestRepay);
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
        uint256 initialShares = vault.balanceOf(anyAddress);
        if (burned > initialShares) burned = initialShares;

        vm.warp(newTimestamp);
        uint256 lockedProfits = currentProfits.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );
        uint256 lockedLosses = currentLosses.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );
        // Necessary to avoid overflow
        vm.startPrank(anyAddress);
        vault.approve(address(this), burned);
        vm.stopPrank();
        uint256 increasedAssets = vault.directBurn(burned, anyAddress);
        assertTrue(vault.balanceOf(anyAddress) == initialShares - burned);

        _nativeStateCheck(
            feeUnlockTime,
            totalSupply - burned,
            balanceOf,
            netLoans,
            newTimestamp,
            lockedProfits + increasedAssets,
            lockedLosses
        );
    }

    function testBorrow(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 borrowed
    ) public {
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        vm.assume(borrowed < vault.freeLiquidity());
        uint256 initialBalance = token.balanceOf(receiver);
        vault.borrow(borrowed, receiver);

        assertTrue(token.balanceOf(receiver) == initialBalance + borrowed);

        _nativeStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf - borrowed,
            netLoans + borrowed,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testRepay(
        uint256 feeUnlockTime,
        uint256 totalSupply,
        uint256 balanceOf,
        uint256 netLoans,
        uint256 latestRepay,
        uint256 currentProfits,
        uint256 currentLosses,
        uint256 newTimestamp,
        uint256 debt,
        uint256 repaid
    ) public {
        // 30 billion years and not going backwards in time
        vm.assume(newTimestamp <= 1e18 && newTimestamp >= latestRepay);
        _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        vm.warp(newTimestamp);
        uint256 lockedProfits = currentProfits.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );
        uint256 lockedLosses = currentLosses.safeMulDiv(
            feeUnlockTime.positiveSub(newTimestamp - latestRepay),
            feeUnlockTime
        );

        if (repaid > token.balanceOf(repayer)) {
            vm.assume(repaid - token.balanceOf(repayer) <= token.balanceOf(tokenSink));
            vm.startPrank(tokenSink);
            token.transfer(repayer, repaid - token.balanceOf(repayer));
            vm.stopPrank();
        }
        if (debt > netLoans) debt = netLoans;
        vm.startPrank(repayer);
        token.approve(address(vault), repaid);
        vm.stopPrank();
        vault.repay(repaid, debt, repayer);

        uint256 newProfits;
        uint256 newLosses;
        if (debt > repaid) newLosses = debt - repaid;
        else newProfits = repaid - debt;

        _nativeStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf + repaid,
            netLoans - debt,
            newTimestamp,
            lockedProfits + newProfits,
            lockedLosses + newLosses
        );
    }
}
