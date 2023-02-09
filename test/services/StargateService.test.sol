// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { StargateService } from "../../src/services/debit/StargateService.sol";
import { IStargatePool } from "../../src/interfaces/external/stargate/IStargateLPStaking.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract StargateServiceTest is PRBTest, StdCheats, BaseServiceTest {
    IManager internal immutable manager;
    StargateService internal immutable service;
    address internal constant stargateRouter = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address internal constant stargateLPStaking = 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b;
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant usdcWhale = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant lpToken = 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56;
    uint16 internal constant usdcPoolID = 1;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16448665);
        vm.selectFork(forkId);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new StargateService(address(manager), stargateRouter, stargateLPStaking);
        vm.stopPrank();
    }

    function setUp() public {
        usdc.approve(address(service), type(uint256).max);

        vm.deal(usdcWhale, 1 ether);

        vm.startPrank(admin);
        // Create Vault: usdc
        manager.create(address(usdc));
        // No caps for this service -> 100% of the liquidity can be used initially
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION);

        service.addPool(address(usdc), 0);

        vm.stopPrank();
    }

    function _prepareVaultsAndUser(uint256 usdcAmount, uint256 usdcMargin) internal returns (uint256, uint256) {
        // Modifications to be sure usdcAmount + usdcMargin <= usdc.balanceOf(usdcWhale) and same for weth
        usdcAmount = usdcAmount % usdc.balanceOf(usdcWhale);
        usdcMargin = usdcMargin % (usdc.balanceOf(usdcWhale) - usdcAmount);
        usdcAmount++;
        usdcMargin++;

        // Fill usdc vault
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcMargin);
        usdc.approve(address(usdcVault), usdcAmount);
        usdcVault.deposit(usdcAmount, usdcWhale);
        vm.stopPrank();

        return (usdcAmount, usdcMargin);
    }

    function _createOrder(uint256 usdcLoan, uint256 usdcMargin) internal returns (IService.Order memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory loans = new uint256[](1);
        loans[0] = usdcLoan;

        uint256[] memory margins = new uint256[](1);
        margins[0] = usdcMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = lpToken;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = usdcLoan + usdcMargin;

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );
        return order;
    }

    function _expectedMintedTokens(uint256 amount) internal view returns (uint256 expected) {
        IStargatePool pool = IStargatePool(lpToken);

        uint256 amountSD = amount / pool.convertRate();
        uint256 mintFeeSD = (amountSD * pool.mintFeeBP()) / 10000;
        amountSD = amountSD - mintFeeSD;
        expected = (amountSD * pool.totalSupply()) / pool.totalLiquidity();
    }

    function _openOrder(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin)
        internal
        returns (uint256, uint256, uint256, bool)
    {
        (usdcAmount, usdcMargin) = _prepareVaultsAndUser(usdcAmount, usdcMargin);
        bool success = true;
        // Loan must be less than amount otherwise Vault will revert
        // Since usdcAmount > 0, the following does not revert for division by zero
        usdcLoan = usdcLoan % usdcAmount;
        IService.Order memory order = _createOrder(usdcLoan, usdcMargin);
        if (_expectedMintedTokens(usdcLoan + usdcMargin) == 0) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("AmountTooLow()"))));
            service.open(order);
            success = false;
        } else service.open(order);

        return (usdcAmount, usdcLoan, usdcMargin, success);
    }

    function testOpen(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin) public {
        (usdcAmount, usdcLoan, usdcMargin, ) = _openOrder(usdcAmount, usdcLoan, usdcMargin);
    }

    function testClose(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin, uint256 minAmountsOutusdc) public {
        bool success;
        (usdcAmount, usdcLoan, usdcMargin, success) = _openOrder(usdcAmount, usdcLoan, usdcMargin);

        // TODO: add slippage check
        uint256 minAmountsOutusdc = 0;
        bytes memory data = abi.encode(minAmountsOutusdc);
        if (success) {
            (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
            if (collaterals[0].amount < minAmountsOutusdc) {
                // Slippage check
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
                service.close(0, data);
            } else {
                service.close(0, data);
            }
        }
    }

    function testQuote(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin) public {
        bool success;
        (usdcAmount, usdcLoan, usdcMargin, success) = _openOrder(usdcAmount, usdcLoan, usdcMargin);
        if (success) {
            (
                IService.Loan[] memory loan,
                IService.Collateral[] memory collaterals,
                uint256 createdAt,
                IService.Status status
            ) = service.getAgreement(1);

            IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);
            (uint256[] memory profits, ) = service.quote(agreement);
        }
    }
}
