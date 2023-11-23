// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { IManager, Manager } from "../src/Manager.sol";

/// @dev Manager native state:
/// bytes32 public constant override salt = "ithil";
/// mapping(address => address) public override vaults;
/// mapping(address => mapping(address => RiskParams)) public riskParams;

/// @dev Manager underlying Vault state
/// --> see Vault test

contract ManagerTest is Test {
    using Math for uint256;

    Manager internal immutable manager;
    ERC20PresetMinterPauser internal immutable firstToken;
    ERC20PresetMinterPauser internal immutable secondToken;
    ERC20PresetMinterPauser internal immutable spuriousToken;
    address internal firstVault;
    address internal secondVault;
    address internal tokenSink;
    address internal notOwner;
    address internal anyAddress;
    address internal debitCustody;
    address internal debitServiceOne;
    address internal debitServiceTwo;

    constructor() {
        manager = new Manager();
        firstToken = new ERC20PresetMinterPauser("firstToken", "FIRSTTOKEN");
        secondToken = new ERC20PresetMinterPauser("secondToken", "SECONDTOKEN");
        spuriousToken = new ERC20PresetMinterPauser("spuriousToken", "THIRDTOKEN");
        tokenSink = address(uint160(uint256(keccak256(abi.encodePacked("Sink")))));
        firstToken.mint(tokenSink, type(uint256).max);
        secondToken.mint(tokenSink, type(uint256).max);
        spuriousToken.mint(tokenSink, type(uint256).max);
        vm.startPrank(tokenSink);
        firstToken.transfer(address(this), 1);
        secondToken.transfer(address(this), 1);
        vm.stopPrank();
        firstToken.approve(address(manager), 1);
        secondToken.approve(address(manager), 1);
    }

    function setUp() public {
        firstVault = manager.create(address(firstToken));
        secondVault = manager.create(address(secondToken));
        notOwner = address(uint160(uint256(keccak256(abi.encodePacked("Not Owner")))));
        anyAddress = address(uint160(uint256(keccak256(abi.encodePacked("Any Address")))));
        debitCustody = address(uint160(uint256(keccak256(abi.encodePacked("Debit Custody")))));
        debitServiceOne = address(uint160(uint256(keccak256(abi.encodePacked("debitServiceOne")))));
        debitServiceTwo = address(uint160(uint256(keccak256(abi.encodePacked("debitServiceTwo")))));
    }

    function testBase() public {
        assertTrue(manager.vaults(address(firstToken)) == firstVault);
        assertTrue(manager.vaults(address(secondToken)) == secondVault);
    }

    function testAccess(uint256 spread, uint256 cap, uint256 feeUnlockTime) public {
        vm.startPrank(anyAddress);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.create(address(spuriousToken));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.setCap(debitServiceOne, address(firstToken), cap, type(uint256).max);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.setFeeUnlockTime(address(firstToken), feeUnlockTime);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.sweep(address(firstToken), address(spuriousToken), anyAddress);
    }

    function testCreate() public {
        vm.prank(tokenSink);
        spuriousToken.transfer(address(this), 1);
        spuriousToken.approve(address(manager), 1);
        address spuriousVault = manager.create(address(spuriousToken));
        assertTrue(manager.vaults(address(spuriousToken)) == spuriousVault);
    }

    function _setupArbitraryState(uint256 previousDeposit, uint256 cap) private returns (uint256) {
        address vaultAddress = manager.vaults(address(firstToken));
        if (previousDeposit == type(uint256).max) previousDeposit--;
        vm.startPrank(tokenSink);
        firstToken.approve(vaultAddress, previousDeposit);
        IVault(vaultAddress).deposit(previousDeposit, anyAddress);
        vm.stopPrank();

        // Take only meaningful caps
        cap = (cap % 1e18) + 1;

        manager.setCap(debitServiceOne, address(firstToken), cap, type(uint256).max);
        (uint256 storedCap, , ) = manager.caps(debitServiceOne, address(firstToken));
        assertTrue(storedCap == cap);
        return cap;
    }

    function testSetCap(uint256 previousDeposit, uint256 debitCap, uint256 cap) public {
        _setupArbitraryState(previousDeposit, debitCap);
        manager.setCap(debitServiceOne, address(firstToken), cap, type(uint256).max);
        (uint256 storedCap, , ) = manager.caps(debitServiceOne, address(firstToken));
        assertTrue(storedCap == cap);
    }

    function testFeeUnlockTime(uint256 previousDeposit, uint256 debitCap, uint256 feeUnlockTime) public {
        _setupArbitraryState(previousDeposit, debitCap);
        feeUnlockTime = Math.min((feeUnlockTime % (7 days)) + 30 seconds, 7 days);
        manager.setFeeUnlockTime(address(firstToken), feeUnlockTime);
        assertTrue(IVault(manager.vaults(address(firstToken))).feeUnlockTime() == feeUnlockTime);
    }

    function testSweep(uint256 spuriousAmount) public {
        vm.prank(tokenSink);
        spuriousToken.transfer(firstVault, spuriousAmount);
        assertTrue(spuriousToken.balanceOf(firstVault) == spuriousAmount);

        uint256 firstBalance = spuriousToken.balanceOf(anyAddress);
        manager.sweep(address(firstToken), address(spuriousToken), anyAddress);

        assertTrue(spuriousToken.balanceOf(anyAddress) == firstBalance + spuriousAmount);
        assertTrue(spuriousToken.balanceOf(firstVault) == 0);
    }

    function testLockVault() public {
        manager.toggleVaultLock(address(firstToken));
        address vaultAddress = manager.vaults(address(firstToken));
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Locked()"))));
        IVault(vaultAddress).deposit(1e18, anyAddress);

        manager.setCap(debitServiceOne, address(firstToken), 1e18, type(uint256).max);
        vm.startPrank(debitServiceOne);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Locked()"))));
        manager.borrow(address(firstToken), 1e18, 0, anyAddress);
        vm.stopPrank();
    }

    function testBorrow(uint256 previousDeposit, uint256 debitCap, uint256 borrowed, uint256 loan) public {
        address vaultAddress = manager.vaults(address(firstToken));
        debitCap = _setupArbitraryState(previousDeposit, debitCap);
        uint256 freeLiquidity = IVault(vaultAddress).freeLiquidity();
        (, , uint256 currentExposure) = manager.caps(debitServiceOne, address(firstToken));

        // Avoid revert due to insufficient free liquidity
        borrowed = freeLiquidity == 0 ? 0 : borrowed % freeLiquidity;

        // Loan must always be less than the actual borrowed quantity
        loan = loan % (borrowed + 1);

        uint256 investedPortion = freeLiquidity == 0
            ? 1e18
            : uint256(1e18).mulDiv(
                (currentExposure + loan),
                (freeLiquidity - borrowed) + (IVault(vaultAddress).netLoans() + loan)
            );
        if (investedPortion > debitCap) {
            manager.setCap(debitServiceOne, address(firstToken), investedPortion, type(uint256).max);
        }
        if (borrowed > 0) {
            vm.prank(debitServiceOne);
            manager.borrow(address(firstToken), borrowed, loan, anyAddress);
        }
    }

    function testRepay(uint256 previousDeposit, uint256 debitCap, uint256 repaid, uint256 debt) public {
        debitCap = _setupArbitraryState(previousDeposit, debitCap);
        vm.assume(repaid <= firstToken.balanceOf(tokenSink));
        vm.startPrank(tokenSink);
        firstToken.approve(manager.vaults(address(firstToken)), repaid);
        vm.stopPrank();

        vm.prank(debitServiceOne);
        manager.repay(address(firstToken), repaid, debt, tokenSink);
    }
}
