// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { SushiService } from "../../src/services/debit/SushiService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { Math } from "../../src/libraries/external/Uniswap/Math.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract SushiServiceTest is PRBTest, StdCheats, BaseServiceTest {
    using GeneralMath for uint256;

    IManager internal immutable manager;
    SushiService internal immutable service;
    IERC20 internal constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address internal constant usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant wethWhale = usdcWhale;
    address internal constant sushirouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant minichef = 0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3;
    uint256 internal constant poolID = 0;
    address internal constant sushiLp = 0x905dfCD5649217c42684f23958568e533C711Aa3;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), 55895589);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new SushiService(address(manager), sushirouter, minichef);
        vm.stopPrank();
    }

    function setUp() public {
        usdc.approve(address(service), type(uint256).max);
        weth.approve(address(service), type(uint256).max);

        vm.deal(usdcWhale, 1 ether);
        vm.deal(wethWhale, 1 ether);

        vm.startPrank(admin);
        manager.create(address(usdc));
        manager.create(address(weth));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION);

        service.addPool(sushiLp, poolID, [address(weth), address(usdc)]);
        vm.stopPrank();
    }

    function _prepareVaultsAndUser(uint256 usdcAmount, uint256 usdcMargin, uint256 wethAmount, uint256 wethMargin)
        internal
        returns (uint256, uint256, uint256, uint256)
    {
        // Modifications to be sure usdcAmount + usdcMargin <= usdc.balanceOf(usdcWhale) and same for weth
        usdcAmount = usdcAmount % usdc.balanceOf(usdcWhale);
        usdcMargin = usdcMargin % (usdc.balanceOf(usdcWhale) - usdcAmount);
        wethAmount = wethAmount % weth.balanceOf(wethWhale);
        wethMargin = wethMargin % (weth.balanceOf(wethWhale) - wethAmount);

        // UniswapV2Library: INSUFFICIENT_AMOUNT will be thrown by Uniswap quote function
        // when trying to deploy zero liquidity: we enforce it to be at least 1
        if (usdcAmount == 0) usdcAmount++;
        if (wethAmount == 0) wethAmount++;
        if (usdcMargin == 0) usdcMargin++;
        if (wethMargin == 0) wethMargin++;

        // Fill usdc vault
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcMargin);
        usdc.approve(address(usdcVault), usdcAmount);
        usdcVault.deposit(usdcAmount, usdcWhale);
        vm.stopPrank();

        // Fill WETH vault
        IVault wethVault = IVault(manager.vaults(address(weth)));
        vm.startPrank(wethWhale);
        weth.transfer(address(this), wethMargin);
        weth.approve(address(wethVault), wethAmount);
        wethVault.deposit(wethAmount, wethWhale);
        vm.stopPrank();
        return (usdcAmount, usdcMargin, wethAmount, wethMargin);
    }

    function _createOrder(uint256 usdcLoan, uint256 usdcMargin, uint256 wethLoan, uint256 wethMargin)
        internal
        returns (IService.Order memory)
    {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        uint256[] memory loans = new uint256[](2);
        loans[0] = wethLoan;
        loans[1] = usdcLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = wethMargin;
        margins[1] = usdcMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = sushiLp;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

        // Slippage protection prevents price to move too much while liquidity is provided
        // TODO: add slippage checks

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            abi.encode([uint256(0), uint256(0)])
        );
        return order;
    }

    function _calculateDeposit(uint256 usdcLoan, uint256 usdcMargin, uint256 wethLoan, uint256 wethMargin)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        (, bytes memory wethQuotedData) = sushirouter.staticcall(
            abi.encodeWithSignature(
                "quote(uint256,uint256,uint256)",
                wethMargin + wethLoan,
                weth.balanceOf(sushiLp),
                usdc.balanceOf(sushiLp)
            )
        );
        (, bytes memory usdcQuotedData) = sushirouter.staticcall(
            abi.encodeWithSignature(
                "quote(uint256,uint256,uint256)",
                usdcMargin + usdcLoan,
                usdc.balanceOf(sushiLp),
                weth.balanceOf(sushiLp)
            )
        );
        uint256 amountA;
        uint256 amountB;
        if (abi.decode(wethQuotedData, (uint256)) <= usdcLoan + usdcMargin) {
            (amountA, amountB) = (wethLoan + wethMargin, abi.decode(wethQuotedData, (uint256)));
        } else {
            (amountA, amountB) = (abi.decode(usdcQuotedData, (uint256)), usdcLoan + usdcMargin);
        }
        return (amountA, amountB, _calculateFees(amountA, amountB));
    }

    function _calculateFees(uint256 amountA, uint256 amountB) internal view returns (uint256) {
        (, bytes memory klast) = sushiLp.staticcall(abi.encodeWithSignature("kLast()"));
        uint256 rootK = Math.sqrt((weth.balanceOf(sushiLp) + amountA) * (usdc.balanceOf(sushiLp) + amountB));
        uint256 rootKLast = Math.sqrt(abi.decode(klast, (uint256)));
        return (IERC20(sushiLp).totalSupply() * (rootK - rootKLast)) / (5 * rootK + rootKLast);
    }

    function _openOrder(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) internal returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (usdcAmount, usdcMargin, wethAmount, wethMargin) = _prepareVaultsAndUser(
            usdcAmount,
            usdcMargin,
            wethAmount,
            wethMargin
        );
        // Loan must be less than amount otherwise Vault will revert
        // Since usdcAmount > 0 and wethAmount > 0, the following does not revert for division by zero
        usdcLoan = usdcLoan % usdcAmount;
        wethLoan = wethLoan % wethAmount;
        IService.Order memory order = _createOrder(usdcLoan, usdcMargin, wethLoan, wethMargin);

        (uint256 wethQuoted, uint256 usdcQuoted, uint256 fees) = _calculateDeposit(
            usdcLoan,
            usdcMargin,
            wethLoan,
            wethMargin
        );

        if (
            wethQuoted * (IERC20(sushiLp).totalSupply() + fees) < weth.balanceOf(sushiLp) ||
            usdcQuoted * (IERC20(sushiLp).totalSupply() + fees) < usdc.balanceOf(sushiLp)
        ) {
            vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
            service.open(order);
        } else service.open(order);
        return (usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin);
    }

    function testOpen(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        uint256 timestamp = block.timestamp;
        (usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin) = _openOrder(
            usdcAmount,
            usdcLoan,
            usdcMargin,
            wethAmount,
            wethLoan,
            wethMargin
        );

        if (service.id() > 0) {
            (
                IService.Loan[] memory loan,
                IService.Collateral[] memory collateral,
                uint256 createdAt,
                IService.Status status
            ) = service.getAgreement(1);

            assertTrue(loan[0].token == address(weth));
            assertTrue(loan[0].amount == wethLoan);
            assertTrue(loan[0].margin == wethMargin);
            assertTrue(loan[1].token == address(usdc));
            assertTrue(loan[1].amount == usdcLoan);
            assertTrue(loan[1].margin == usdcMargin);
            assertTrue(collateral[0].token == sushiLp);
            assertTrue(collateral[0].identifier == 0);
            assertTrue(collateral[0].itemType == IService.ItemType.ERC20);
            assertTrue(createdAt == timestamp);
            assertTrue(status == IService.Status.OPEN);
        }
    }

    function testClose(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin,
        uint256 minAmountsOutusdc,
        uint256 minAmountsOutWeth
    ) public {
        (usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin) = _openOrder(
            usdcAmount,
            usdcLoan,
            usdcMargin,
            wethAmount,
            wethLoan,
            wethMargin
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;
        bytes memory data = abi.encode(minAmountsOut);

        if (service.id() > 0) {
            (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);

            uint256 balanceWeth = weth.balanceOf(sushiLp);
            uint256 balanceUsdc = usdc.balanceOf(sushiLp);
            uint256 fees = _calculateFees(balanceWeth, balanceUsdc);
            uint256 totalSupply = IERC20(sushiLp).totalSupply() + fees;
            if (
                collaterals[0].amount * balanceWeth < totalSupply || collaterals[0].amount * balanceUsdc < totalSupply
            ) {
                vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
                service.close(0, data);
            } else service.close(0, data);
        }
    }

    function testQuote(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        (usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin) = _openOrder(
            usdcAmount,
            usdcLoan,
            usdcMargin,
            wethAmount,
            wethLoan,
            wethMargin
        );

        if (service.id() > 0) {
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
