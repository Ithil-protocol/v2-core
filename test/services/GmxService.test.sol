// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { GmxService } from "../../src/services/debit/GmxService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";

contract GmxServiceTest is BaseIntegrationServiceTest {
    GmxService internal immutable service;

    address internal constant gmxRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address internal constant gmxRouterV2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address internal constant glpRewardTracker = 0xd2D1162512F927a7e282Ef43a362659E4F2a728F;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // USDC Native
    address internal constant whale = 0x8b8149Dd385955DC1cE77a4bE7700CCD6a212e65;
    // USDC whale cannot be GMX itself, or it will break the contract!
    address internal constant usdcWhale = 0xE68Ee8A12c611fd043fB05d65E1548dC1383f2b9;
    uint256 internal constant amount = 1 * 1e18; // 1 WETH
    uint256 internal constant usdcAmount = 1e10; // 10k USDC

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.deal(admin, 1 ether);
        vm.deal(whale, 1 ether);

        vm.prank(admin);
        service = new GmxService(address(manager), gmxRouter, gmxRouterV2, 30 * 86400);
    }

    function _equalityWithTolerance(uint256 amount1, uint256 amount2, uint256 tolerance) internal {
        assertGe(amount1 + tolerance, amount2);
        assertGe(amount2 + tolerance, amount1);
    }

    function setUp() public override {
        weth.approve(address(service), type(uint256).max);
        usdc.approve(address(service), type(uint256).max);

        vm.prank(whale);
        weth.transfer(admin, 1);
        vm.prank(usdcWhale);
        usdc.transfer(admin, 1);
        vm.startPrank(admin);
        weth.approve(address(manager), 1);
        usdc.approve(address(manager), 1);
        manager.create(address(weth));
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION, type(uint256).max);
        manager.create(address(usdc));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(whale);
        weth.transfer(address(this), 1e18);
        IVault vault = IVault(manager.vaults(address(weth)));
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(amount, whale);
        vm.stopPrank();

        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcAmount);
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        usdc.approve(address(usdcVault), type(uint256).max);
        usdcVault.deposit(usdcAmount, whale);
        vm.stopPrank();
    }

    function testGmxIntegration(uint256 loanAmount, uint256 margin) private {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % 1e18;

        uint256[] memory margins = new uint256[](1);
        margins[0] = (margin % 9e17) + 1e17;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

        uint256 initial = weth.balanceOf(address(this)) - margins[0];

        IService.Order memory order = OrderHelper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );

        service.open(order);

        (IService.Loan[] memory loan, IService.Collateral[] memory collaterals, uint256 createdAt, ) = service
            .getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, IService.Status.OPEN);

        service.close(0, abi.encode(uint256(1)));
        assertEq(weth.balanceOf(address(this)), initial + service.quote(agreement)[0] - loans[0]);
    }

    function testGmxIntegrationUsdc(uint256 loanAmount, uint256 margin) public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % usdcAmount;

        uint256[] memory margins = new uint256[](1);
        margins[0] = (margin % 9e7) + 1e8;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = ((loans[0] + margins[0]) * 99 * 1e12) / 100;

        uint256 initial = usdc.balanceOf(address(this)) - margins[0];

        IService.Order memory order = OrderHelper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );

        service.open(order);

        (IService.Loan[] memory loan, IService.Collateral[] memory collaterals, uint256 createdAt, ) = service
            .getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, IService.Status.OPEN);

        service.close(0, abi.encode(uint256(1)));
        _equalityWithTolerance(usdc.balanceOf(address(this)), initial + service.quote(agreement)[0] - loans[0], 1);
    }
}
