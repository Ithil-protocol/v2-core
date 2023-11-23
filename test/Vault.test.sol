// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { IVault, Vault } from "../src/Vault.sol";
import { GeneralMath } from "./helpers/GeneralMath.sol";
import { SignUtils } from "./helpers/SignUtils.sol";
import { PermitToken } from "./helpers/PermitToken.sol";

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

contract VaultTest is Test {
    using Math for uint256;
    using GeneralMath for uint256;

    Vault internal immutable vault;
    PermitToken internal immutable token;
    ERC20PresetMinterPauser internal immutable spuriousToken;
    address internal immutable tokenSink;
    address internal immutable notOwner;
    address internal immutable anyAddress;
    address internal immutable depositor;
    address internal immutable receiver;
    address internal immutable borrower;
    address internal immutable repayer;

    constructor() {
        token = new PermitToken("test", "TEST");
        vault = new Vault(IERC20Metadata(address(token)));
        tokenSink = address(uint160(uint256(keccak256(abi.encodePacked("Sink")))));
        notOwner = address(uint160(uint256(keccak256(abi.encodePacked("Not Owner")))));
        anyAddress = address(uint160(uint256(keccak256(abi.encodePacked("Any Address")))));
        depositor = address(uint160(uint256(keccak256(abi.encodePacked("Depositor")))));
        receiver = address(uint160(uint256(keccak256(abi.encodePacked("Receiver")))));
        repayer = address(uint160(uint256(keccak256(abi.encodePacked("Repayer")))));
        borrower = address(uint160(uint256(keccak256(abi.encodePacked("Borrower")))));
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
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedToOwner()"))));
        vault.setFeeUnlockTime(1000);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedToOwner()"))));
        vault.sweep(anyAddress, address(spuriousToken));
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedToOwner()"))));
        vault.borrow(assets, assets, anyAddress);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedToOwner()"))));
        vault.repay(assets, debt, anyAddress);
        vm.stopPrank();
    }

    function _originalStateCheck(
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
    ) internal returns (uint256, uint256) {
        // Force fee unlock time to be within range
        feeUnlockTime = Math.min((feeUnlockTime % (7 days)) + 30 seconds, 7 days);
        vault.setFeeUnlockTime(feeUnlockTime);

        // Set totalSupply by depositing
        vm.prank(tokenSink);
        token.transfer(depositor, totalSupply);
        vm.startPrank(depositor);
        token.approve(address(vault), totalSupply);
        vault.deposit(totalSupply, receiver);
        vm.stopPrank();

        // Set latestRepay
        vm.warp(latestRepay);
        vault.repay(0, 0, repayer);

        // Set currentProfits (assume this otherwise there are no tokens available)
        currentProfits = Math.min(currentProfits, token.totalSupply() - totalSupply);
        vm.prank(tokenSink);
        token.transfer(repayer, currentProfits);
        vm.prank(repayer);
        token.approve(address(vault), currentProfits);
        vault.repay(currentProfits, 0, repayer);

        // Set currentLosses
        vm.assume(currentLosses < vault.freeLiquidity());
        vault.borrow(currentLosses, currentLosses, borrower);
        vault.repay(0, currentLosses, repayer);

        // Set netLoans
        vm.assume(netLoans < vault.freeLiquidity());
        vault.borrow(netLoans, netLoans, borrower);

        // Set balanceOf by adjusting
        vm.assume(balanceOf > 0); // Otherwise it fails due to unhealthy vault
        uint256 initialBalance = token.balanceOf(address(vault));
        // TODO: remove first assumption (the second is necessary because totalSupply is fixed)
        vm.assume(balanceOf > initialBalance && balanceOf - initialBalance <= token.balanceOf(tokenSink));
        vm.prank(tokenSink);
        token.transfer(address(vault), balanceOf - initialBalance);

        _originalStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
        return (feeUnlockTime, currentProfits);
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
        if (feeUnlockTimeSet < 30 || feeUnlockTimeSet > 7 days) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("FeeUnlockTimeOutOfRange()"))));
            vault.setFeeUnlockTime(feeUnlockTimeSet);
        } else {
            vault.setFeeUnlockTime(feeUnlockTimeSet);
            assertTrue(vault.feeUnlockTime() == feeUnlockTimeSet);
            feeUnlockTime = feeUnlockTimeSet;
        }
        // Recheck the remaining state is unchanged (except feeUnlockTime but it's already reassigned)
        _originalStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
        _originalStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
        uint256 shares = vault.deposit(deposited, receiver);
        vm.stopPrank();

        // Specific addresses' state changes
        assertTrue(vault.balanceOf(address(receiver)) == initialReceiverShares + shares);
        assertTrue(vault.balanceOf(address(depositor)) == initialDepositorShares);

        // Vault state change
        _originalStateCheck(
            feeUnlockTime,
            initialVaultTotalSupply + shares,
            initialVaultAssets + deposited,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );
    }

    function testDepositWithPermit(uint256 amount) public {
        SignUtils utils = new SignUtils(token.DOMAIN_SEPARATOR());
        uint256 signerPrivateKey = 0xA11CE;
        address signer = vm.addr(signerPrivateKey);
        vm.deal(signer, 1 ether);

        SignUtils.Permit memory permit = SignUtils.Permit({
            owner: signer,
            spender: address(vault),
            value: amount,
            nonce: 0,
            deadline: 1 seconds
        });
        bytes32 digest = utils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        deal({ token: address(token), to: signer, give: amount });
        vm.prank(signer);
        uint256 shares = vault.depositWithPermit(permit.value, receiver, permit.deadline, v, r, s);
        assertTrue(vault.balanceOf(address(receiver)) == shares);
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
        if (vault.totalAssets() > 0 && vault.totalSupply() > 0) {
            vm.assume(minted / vault.totalSupply() < (type(uint256).max / vault.totalAssets()));
        }
        uint256 deposited = vault.previewMint(minted);

        // Necessary assumption because token totalSupply is fixed
        if (deposited > initialDepositorAssets) {
            vm.assume(deposited - initialDepositorAssets < token.balanceOf(tokenSink));
            vm.prank(tokenSink);
            token.transfer(depositor, deposited - initialDepositorAssets);
        }

        vm.startPrank(depositor);
        token.approve(address(vault), deposited);
        vault.mint(minted, receiver);
        vm.stopPrank();

        // Specific addresses' state changes
        assertTrue(vault.balanceOf(address(receiver)) == initialReceiverShares + minted);
        assertTrue(vault.balanceOf(address(depositor)) == initialDepositorShares);

        // Vault state change
        _originalStateCheck(
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
            vault.withdraw(withdrawn, receiver, receiver);
            withdrawn = 0;
        }

        shares = vault.withdraw(withdrawn, receiver, receiver);
        assertTrue(vault.balanceOf(receiver) == initialReceiverShares - shares);
        assertTrue(token.balanceOf(receiver) == initialReceiverAssets + withdrawn);

        vm.stopPrank();

        // Vault state change
        _originalStateCheck(
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
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
            vault.redeem(redeemed, receiver, receiver);
            redeemed = 0;
            withdrawn = 0;
        }
        vault.redeem(redeemed, receiver, receiver);
        assertTrue(vault.balanceOf(receiver) == initialReceiverShares - redeemed);
        assertTrue(token.balanceOf(receiver) == initialReceiverAssets + withdrawn);

        vm.stopPrank();

        // Vault state change
        _originalStateCheck(
            feeUnlockTime,
            totalSupply - redeemed,
            balanceOf - withdrawn,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
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
        uint256 borrowed,
        uint256 loan
    ) public {
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
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
        loan = borrowed == 0 ? 0 : loan % borrowed;
        vault.borrow(borrowed, loan, receiver);

        assertTrue(token.balanceOf(receiver) == initialBalance + borrowed);

        _originalStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf - borrowed,
            netLoans.safeAdd(loan),
            latestRepay,
            currentProfits,
            currentLosses + (borrowed - loan)
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
        uint256 timePast,
        uint256 debt,
        uint256 repaid
    ) public {
        (feeUnlockTime, currentProfits) = _setupArbitraryState(
            feeUnlockTime,
            totalSupply,
            balanceOf,
            netLoans,
            latestRepay,
            currentProfits,
            currentLosses
        );

        uint256 newTimestamp = latestRepay.safeAdd(timePast);
        vm.warp(newTimestamp);
        uint256 lockedProfits;
        uint256 lockedLosses;
        (lockedProfits, lockedLosses, , ) = vault.getFeeStatus();
        lockedProfits = lockedProfits.mulDiv(
            feeUnlockTime - Math.min(block.timestamp - latestRepay, feeUnlockTime),
            feeUnlockTime
        );
        lockedLosses = lockedLosses.mulDiv(
            feeUnlockTime - Math.min(block.timestamp - latestRepay, feeUnlockTime),
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

        _originalStateCheck(
            feeUnlockTime,
            totalSupply,
            balanceOf + repaid,
            netLoans - debt,
            newTimestamp,
            lockedProfits + (debt < repaid ? repaid - debt : 0),
            lockedLosses + (debt > repaid ? debt - repaid : 0)
        );
    }

    function testCannotWithdrawMoreThanFreeLiquidity(uint256 amount) public {
        vm.startPrank(tokenSink);
        token.approve(address(vault), amount);
        vault.deposit(amount, receiver);
        vm.stopPrank();

        // withdraw without leaving 1 token unit
        uint256 vaultBalance = token.balanceOf(address(vault));
        vm.expectRevert(IVault.InsufficientLiquidity.selector);
        vault.withdraw(vaultBalance, tokenSink, receiver);
    }

    function testCannotBorrowMoreThanFreeLiquidity(uint256 amount) public {
        vm.startPrank(tokenSink);
        token.approve(address(vault), amount);
        vault.deposit(amount, receiver);
        vm.stopPrank();

        uint256 vaultBalance = token.balanceOf(address(vault));
        vm.expectRevert(IVault.InsufficientFreeLiquidity.selector);
        vault.borrow(vaultBalance, vaultBalance, address(this));
    }
}
