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

/// @dev Manager native state:
/// bytes32 public constant override salt = "ithil";
/// mapping(address => address) public override vaults;
/// mapping(address => mapping(address => RiskParams)) public riskParams;

/// @dev Manager underlying Vault state
/// --> see Vault test

contract ManagerTest is PRBTest, StdCheats {
    using GeneralMath for uint256;

    Manager internal immutable manager;
    ERC20PresetMinterPauser internal immutable firstToken;
    ERC20PresetMinterPauser internal immutable secondToken;
    ERC20PresetMinterPauser internal immutable spuriousToken;
    address internal immutable firstVault;
    address internal immutable secondVault;
    address internal immutable tokenSink;
    address internal immutable notOwner;
    address internal immutable anyAddress;
    address internal immutable creditCustody;
    address internal immutable debitCustody;
    address internal immutable debitServiceOne;
    address internal immutable debitServiceTwo;
    address internal immutable creditServiceOne;
    address internal immutable creditServiceTwo;

    constructor() {
        manager = new Manager();
        firstToken = new ERC20PresetMinterPauser("firstToken", "FIRSTTOKEN");
        secondToken = new ERC20PresetMinterPauser("secondToken", "SECONDTOKEN");
        spuriousToken = new ERC20PresetMinterPauser("spuriousToken", "THIRDTOKEN");
        firstVault = manager.create(address(firstToken));
        secondVault = manager.create(address(secondToken));
        tokenSink = address(uint160(uint(keccak256(abi.encodePacked("Sink")))));
        notOwner = address(uint160(uint(keccak256(abi.encodePacked("Not Owner")))));
        anyAddress = address(uint160(uint(keccak256(abi.encodePacked("Any Address")))));
        creditCustody = address(uint160(uint(keccak256(abi.encodePacked("Credit Custody")))));
        debitCustody = address(uint160(uint(keccak256(abi.encodePacked("Debit Custody")))));
        debitServiceOne = address(uint160(uint(keccak256(abi.encodePacked("debitServiceOne")))));
        debitServiceTwo = address(uint160(uint(keccak256(abi.encodePacked("debitServiceTwo")))));
        creditServiceOne = address(uint160(uint(keccak256(abi.encodePacked("creditServiceOne")))));
        creditServiceTwo = address(uint160(uint(keccak256(abi.encodePacked("creditServiceTwo")))));
    }

    function setUp() public {
        firstToken.mint(tokenSink, type(uint256).max);
        secondToken.mint(tokenSink, type(uint256).max);
        spuriousToken.mint(tokenSink, type(uint256).max);
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
        manager.setSpread(debitServiceOne, address(firstToken), spread);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.setCap(debitServiceOne, address(firstToken), cap);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.setFeeUnlockTime(address(firstToken), feeUnlockTime);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        manager.sweep(anyAddress, address(spuriousToken), firstVault);
    }

    function testCreate() public {
        address spuriousVault = manager.create(address(spuriousToken));
        assertTrue(manager.vaults(address(spuriousToken)) == spuriousVault);
    }

    function _setupArbitraryState(
        uint256 previousDeposit,
        uint256 creditCap,
        uint256 debitCap,
        uint256 creditExposure,
        uint256 debitExposure
    ) private returns (uint256, uint256, uint256, uint256) {
        vm.assume(creditExposure <= type(uint256).max - previousDeposit);
        vm.assume(debitExposure < previousDeposit + creditExposure);
        address vaultAddress = manager.vaults(address(firstToken));
        vm.prank(tokenSink);
        firstToken.approve(vaultAddress, previousDeposit + creditExposure);
        IVault(vaultAddress).deposit(previousDeposit, anyAddress, tokenSink);

        // Take only meaningful caps
        creditCap = (creditCap % GeneralMath.RESOLUTION) + 1;
        debitCap = (debitCap % GeneralMath.RESOLUTION) + 1;

        manager.setCap(creditServiceOne, address(firstToken), creditCap);
        manager.setCap(debitServiceOne, address(firstToken), debitCap);

        // Setup credit exposure
        // Avoid failures due to too high exposure
        uint256 maxCreditExposure = creditCap == GeneralMath.RESOLUTION
            ? type(uint256).max
            : IVault(vaultAddress).totalSupply().safeMulDiv(creditCap, GeneralMath.RESOLUTION - creditCap);
        creditExposure = maxCreditExposure == 0 ? 0 : creditExposure % maxCreditExposure;

        if(GeneralMath.RESOLUTION.safeMulDiv(
            creditExposure,
            IVault(vaultAddress).totalSupply()
        ) > creditCap) {
            creditCap = GeneralMath.RESOLUTION.safeMulDiv(
            creditExposure,
            IVault(vaultAddress).totalSupply()
            );
            manager.setCap(creditServiceOne, address(firstToken), creditCap);
        }
        vm.prank(creditServiceOne);
        manager.deposit(address(firstToken), creditExposure, creditCustody, tokenSink);

        (, uint256 storedCreditCap, uint256 storedCreditExposure) = manager.riskParams(
            creditServiceOne,
            address(firstToken)
        );

        // Setup debit exposure
        uint256 maxDebitExposure = IVault(vaultAddress).freeLiquidity().safeMulDiv(
            debitCap,
            GeneralMath.RESOLUTION
        );
        debitExposure = maxDebitExposure == 0 ? 0 : debitExposure % maxDebitExposure;

        // Check because safeMulDiv is not invertible in the overflow region
        // In case we overflow the cap, increase the cap
        if(GeneralMath.RESOLUTION.safeMulDiv(
            debitExposure,
            IVault(vaultAddress).freeLiquidity()
        ) > debitCap) {
            debitCap = GeneralMath.RESOLUTION.safeMulDiv(
            debitExposure,
            IVault(vaultAddress).freeLiquidity()
            );
            manager.setCap(debitServiceOne, address(firstToken), debitCap);
        }

        vm.prank(debitServiceOne);
        if (debitExposure > 0) manager.borrow(address(firstToken), debitExposure, debitCustody);

        (, uint256 storedDebitCap, uint256 storedDebitExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );

        assertTrue(storedCreditCap == creditCap);
        assertTrue(storedCreditExposure == creditExposure);
        assertTrue(storedDebitCap == debitCap);
        assertTrue(storedDebitExposure == debitExposure);
        return (creditCap, debitCap, creditExposure, debitExposure);
    }

    function testSetSpread(uint256 spread) public {
        manager.setSpread(debitServiceOne, address(firstToken), spread);
        (uint256 storedSpread, uint256 storedCap, uint256 storedExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );
        assertTrue(storedSpread == spread);
        assertTrue(storedCap == 0);
        assertTrue(storedExposure == 0);
    }

    function testSetCap(uint256 cap) public {
        manager.setCap(debitServiceOne, address(firstToken), cap);
        (uint256 storedSpread, uint256 storedCap, uint256 storedExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );
        assertTrue(storedSpread == 0);
        assertTrue(storedCap == cap);
        assertTrue(storedExposure == 0);
    }

    function testFeeUnlockTime(uint256 feeUnlockTime) public {
        feeUnlockTime = GeneralMath.min((feeUnlockTime % (7 days)) + 30 seconds, 7 days);
        manager.setFeeUnlockTime(address(firstToken), feeUnlockTime);
        assertTrue(IVault(manager.vaults(address(firstToken))).feeUnlockTime() == feeUnlockTime);
    }

    function testSweep(uint256 spuriousAmount) public {
        vm.prank(tokenSink);
        spuriousToken.transfer(firstVault, spuriousAmount);
        assertTrue(spuriousToken.balanceOf(firstVault) == spuriousAmount);

        uint256 firstBalance = spuriousToken.balanceOf(anyAddress);
        manager.sweep(anyAddress, address(spuriousToken), firstVault);

        assertTrue(spuriousToken.balanceOf(anyAddress) == firstBalance + spuriousAmount);
        assertTrue(spuriousToken.balanceOf(firstVault) == 0);
    }

    function testDeposit(uint256 amount, uint256 previouslyDeposited, uint256 cap) public {
        // Necessary because tokens are capped
        vm.assume(amount < type(uint256).max - previouslyDeposited);
        address vaultAddress = manager.vaults(address(firstToken));
        // Start with an unpredictable deposit
        vm.startPrank(tokenSink);
        firstToken.approve(vaultAddress, previouslyDeposited + amount);
        IVault(vaultAddress).deposit(previouslyDeposited, anyAddress, tokenSink);
        vm.stopPrank();

        // All tokens come from token sink
        // Set cap for creditServiceOne
        manager.setCap(creditServiceOne, address(firstToken), cap);
        vm.startPrank(creditServiceOne);
        if (cap == 0) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("Restricted_To_Whitelisted_Services()"))));
            manager.deposit(address(firstToken), amount, anyAddress, tokenSink);
        } else {
            uint256 newShares = IVault(vaultAddress).previewDeposit(amount);
            uint256 investedPortion = GeneralMath.RESOLUTION.safeMulDiv(amount, previouslyDeposited + newShares);
            if (investedPortion > cap) {
                ///@dev TODO: how to encode an error with parameters inside?
                vm.expectRevert();
                manager.deposit(address(firstToken), amount, anyAddress, tokenSink);
            } else {
                uint256 initialShares = IVault(vaultAddress).balanceOf(anyAddress);
                uint256 initialBalance = firstToken.balanceOf(vaultAddress);
                uint256 shares = manager.deposit(address(firstToken), amount, anyAddress, tokenSink);
                (, , uint256 storedExposure) = manager.riskParams(creditServiceOne, address(firstToken));
                assertTrue(storedExposure == shares);
                assertTrue(IVault(vaultAddress).balanceOf(anyAddress) == initialShares + shares);
                assertTrue(firstToken.balanceOf(vaultAddress) == initialBalance + amount);
            }
        }
    }

    // function testWithdraw(
    //     uint256 previousDeposit,
    //     uint256 creditCap,
    //     uint256 debitCap,
    //     uint256 creditExposure,
    //     uint256 debitExposure,
    //     uint256 withdrawn
    // ) public {
    //     address vaultAddress = manager.vaults(address(firstToken));
    //     _setupArbitraryState(previousDeposit, creditCap, debitCap, creditExposure, debitExposure);
    //     if(withdrawn >= IVault(vaultAddress).freeLiquidity()) withdrawn = IVault(vaultAddress).freeLiquidity() == 0 ? 0 : withdrawn % IVault(vaultAddress).freeLiquidity();
    //     vm.prank(creditCustody);
    //     IVault(vaultAddress).approve(vaultAddress, IVault(vaultAddress).previewWithdraw(withdrawn));
    //     vm.startPrank(creditServiceOne);
    //     if(withdrawn > 0) manager.withdraw(address(firstToken), withdrawn, creditCustody, anyAddress);
    // }
}
