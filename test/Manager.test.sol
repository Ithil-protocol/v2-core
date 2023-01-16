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
    address internal immutable debitCustody;
    address internal immutable debitServiceOne;
    address internal immutable debitServiceTwo;

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
        debitCustody = address(uint160(uint(keccak256(abi.encodePacked("Debit Custody")))));
        debitServiceOne = address(uint160(uint(keccak256(abi.encodePacked("debitServiceOne")))));
        debitServiceTwo = address(uint160(uint(keccak256(abi.encodePacked("debitServiceTwo")))));
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

    function _setupArbitraryState(uint256 previousDeposit, uint256 debitSpread, uint256 debitCap, uint256 debitExposure)
        private
        returns (uint256, uint256)
    {
        vm.assume(debitExposure < previousDeposit);
        address vaultAddress = manager.vaults(address(firstToken));
        vm.startPrank(tokenSink);
        firstToken.approve(vaultAddress, previousDeposit);
        IVault(vaultAddress).deposit(previousDeposit, anyAddress);
        vm.stopPrank();

        // Take only meaningful caps
        debitCap = (debitCap % GeneralMath.RESOLUTION) + 1;

        manager.setSpread(debitServiceOne, address(firstToken), debitSpread);
        manager.setCap(debitServiceOne, address(firstToken), debitCap);

        // Setup debit exposure
        uint256 maxDebitExposure = IVault(vaultAddress).freeLiquidity().safeMulDiv(debitCap, GeneralMath.RESOLUTION);
        debitExposure = maxDebitExposure == 0 ? 0 : debitExposure % maxDebitExposure;

        // Check because safeMulDiv is not invertible in the overflow region
        // In case we overflow the cap, increase the cap
        if (GeneralMath.RESOLUTION.safeMulDiv(debitExposure, IVault(vaultAddress).freeLiquidity()) > debitCap) {
            debitCap = GeneralMath.RESOLUTION.safeMulDiv(debitExposure, IVault(vaultAddress).freeLiquidity());
            manager.setCap(debitServiceOne, address(firstToken), debitCap);
        }

        vm.prank(debitServiceOne);
        if (debitExposure > 0) manager.borrow(address(firstToken), debitExposure, debitCustody);

        (uint256 storedDebitSpread, uint256 storedDebitCap, uint256 storedDebitExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );

        assertTrue(storedDebitSpread == debitSpread);
        assertTrue(storedDebitCap == debitCap);
        assertTrue(storedDebitExposure == debitExposure);
        return (debitCap, debitExposure);
    }

    function testSetSpread(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 spread
    ) public {
        (uint256 initialCap, uint256 initialExposure) = _setupArbitraryState(
            previousDeposit,
            debitSpread,
            debitCap,
            debitExposure
        );
        manager.setSpread(debitServiceOne, address(firstToken), spread);

        (uint256 storedSpread, uint256 storedCap, uint256 storedExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );
        assertTrue(storedSpread == spread);
        assertTrue(storedCap == initialCap);
        assertTrue(storedExposure == initialExposure);
    }

    function testSetCap(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 cap
    ) public {
        (, uint256 initialExposure) = _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);
        manager.setCap(debitServiceOne, address(firstToken), cap);
        (uint256 storedSpread, uint256 storedCap, uint256 storedExposure) = manager.riskParams(
            debitServiceOne,
            address(firstToken)
        );
        assertTrue(storedSpread == debitSpread);
        assertTrue(storedCap == cap);
        assertTrue(storedExposure == initialExposure);
    }

    function testFeeUnlockTime(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 feeUnlockTime
    ) public {
        _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);
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

    function testBorrow(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 borrowed
    ) public {
        address vaultAddress = manager.vaults(address(firstToken));
        (debitCap, debitExposure) = _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);
        vm.assume(borrowed <= type(uint256).max - debitExposure);

        uint256 currentPortion = GeneralMath.RESOLUTION.safeMulDiv(
            debitExposure,
            IVault(vaultAddress).freeLiquidity().safeAdd(IVault(vaultAddress).netLoans())
        );
        uint256 maxDebitExposure = (IVault(vaultAddress).freeLiquidity().safeAdd(IVault(vaultAddress).netLoans()))
            .safeMulDiv(debitCap - currentPortion, GeneralMath.RESOLUTION);
        borrowed = maxDebitExposure == 0 ? 0 : borrowed % maxDebitExposure;
        // Check because safeMulDiv is not invertible in the overflow region
        // In case we overflow the cap, reduce the borrowed
        if (
            GeneralMath.RESOLUTION.safeMulDiv(
                debitExposure + borrowed,
                IVault(vaultAddress).freeLiquidity().safeAdd(IVault(vaultAddress).netLoans())
            ) > debitCap
        ) {
            debitCap = GeneralMath.RESOLUTION.safeMulDiv(
                debitExposure + borrowed,
                IVault(vaultAddress).freeLiquidity().safeAdd(IVault(vaultAddress).netLoans())
            );
            manager.setCap(debitServiceOne, address(firstToken), debitCap);
        }

        if (borrowed >= IVault(vaultAddress).freeLiquidity()) borrowed = IVault(vaultAddress).freeLiquidity() - 1;
        vm.prank(debitServiceOne);
        manager.borrow(address(firstToken), borrowed, anyAddress);

        (, , uint256 storedDebitExposure) = manager.riskParams(debitServiceOne, address(firstToken));

        assertTrue(storedDebitExposure == debitExposure + borrowed);
    }

    function testRepay(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 repaid,
        uint256 debt
    ) public {
        (debitCap, debitExposure) = _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);
        vm.assume(repaid <= firstToken.balanceOf(tokenSink));
        vm.startPrank(tokenSink);
        firstToken.approve(manager.vaults(address(firstToken)), repaid);
        vm.stopPrank();

        vm.prank(debitServiceOne);
        manager.repay(address(firstToken), repaid, debt, tokenSink);

        (, , uint256 storedDebitExposure) = manager.riskParams(debitServiceOne, address(firstToken));
        assertTrue(storedDebitExposure == debitExposure.positiveSub(debt));
    }

    function testDirectMint(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 minted,
        uint256 maxAmountIn
    ) public {
        IVault vault = IVault(manager.vaults(address(firstToken)));
        (debitCap, debitExposure) = _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);

        // Necessary to avoid overflow
        minted = minted.safeAdd(vault.totalSupply()) - vault.totalSupply();
        if (vault.totalAssets() > 0 && vault.totalSupply() > 0)
            vm.assume(minted / vault.totalSupply() < (type(uint256).max / vault.totalAssets()));

        vm.startPrank(debitServiceOne);
        uint256 increasedAssets = vault.convertToAssets(minted);
        if (increasedAssets > maxAmountIn) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("Max_Amount_Exceeded()"))));
            manager.directMint(address(firstToken), anyAddress, minted, maxAmountIn);
        } else {
            manager.directMint(address(firstToken), anyAddress, minted, maxAmountIn);
        }
    }

    function testDirectBurn(
        uint256 previousDeposit,
        uint256 debitSpread,
        uint256 debitCap,
        uint256 debitExposure,
        uint256 burned,
        uint256 maxAmountIn
    ) public {
        IVault vault = IVault(manager.vaults(address(firstToken)));
        (debitCap, debitExposure) = _setupArbitraryState(previousDeposit, debitSpread, debitCap, debitExposure);

        uint256 initialShares = vault.balanceOf(anyAddress);
        if (burned > initialShares) burned = initialShares;
        // Avoid burning everything
        uint256 totalSupply = vault.totalSupply();
        burned = totalSupply == 0 ? 0 : burned % totalSupply;

        vm.prank(anyAddress);
        vault.approve(address(manager), burned);

        if (burned > 0) {
            vm.startPrank(debitServiceOne);
            uint256 distributedAssets = vault.convertToAssets(burned);
            if (distributedAssets > maxAmountIn) {
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("Max_Amount_Exceeded()"))));
                manager.directBurn(address(firstToken), anyAddress, burned, maxAmountIn);
            } else {
                manager.directBurn(address(firstToken), anyAddress, burned, maxAmountIn);
            }
        }
    }
}
