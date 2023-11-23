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

contract MockRouter {
    uint256 public amount;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    constructor(uint256 _amount) {
        amount = _amount;
    }

    function handleRewards(bool, bool, bool, bool, bool, bool, bool) external {
        weth.transfer(msg.sender, amount);
    }
}

contract GmxServiceTest is BaseIntegrationServiceTest {
    GmxService internal immutable service;

    address internal constant gmxRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address internal constant gmxRouterV2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address internal constant glpRewardTracker = 0xd2D1162512F927a7e282Ef43a362659E4F2a728F;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // USDC Native
    address internal constant whale = 0x0dF5dfd95966753f01cb80E76dc20EA958238C46;
    // USDC whale cannot be GMX itself, or it will break the contract!
    address internal constant usdcWhale = 0xE68Ee8A12c611fd043fB05d65E1548dC1383f2b9;
    uint256 internal constant amount = 1 * 1e20; // 100 WETH
    uint256 internal constant usdcAmount = 1e10; // 10k USDC

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    MockRouter internal mockRouter;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.deal(admin, 1 ether);
        vm.deal(whale, 1 ether);

        mockRouter = new MockRouter(1e16);
        vm.prank(admin);
        service = new GmxService(address(manager), address(mockRouter), gmxRouterV2, 30 * 86400);
    }

    function _equalityWithTolerance(uint256 amount1, uint256 amount2, uint256 tolerance) internal {
        assertGe(amount1 + tolerance, amount2);
        assertGe(amount2 + tolerance, amount1);
    }

    function setUp() public override {
        weth.approve(address(service), type(uint256).max);
        usdc.approve(address(service), type(uint256).max);

        vm.startPrank(whale);
        weth.transfer(admin, 1);
        weth.transfer(address(mockRouter), 1e18);
        vm.stopPrank();
        vm.prank(usdcWhale);
        usdc.transfer(admin, 1);
        vm.startPrank(admin);
        weth.approve(address(manager), 1);
        usdc.approve(address(manager), 1);
        manager.create(address(weth));
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION, type(uint256).max);
        manager.create(address(usdc));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION, type(uint256).max);
        service.setRiskParams(address(weth), 0, 0, 86400);
        service.setRiskParams(address(usdc), 0, 0, 86400);
        vm.stopPrank();

        vm.startPrank(whale);
        weth.transfer(address(this), 1e20);
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

    function _openGmxEth(uint256 loanAmount, uint256 margin) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % 1e18;

        uint256[] memory margins = new uint256[](1);
        margins[0] = margin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

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
    }

    function _openGmxUsdc(uint256 loanAmount, uint256 margin) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % usdcAmount;

        uint256[] memory margins = new uint256[](1);
        margins[0] = margin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = ((loans[0] + margins[0]) * 99 * 1e12) / 100;

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
    }

    function testGmxIntegration(uint256 loanAmount, uint256 margin) public {
        margin = (margin % 9e17) + 1e17;
        uint256 initial = weth.balanceOf(address(this)) - margin;
        _openGmxEth(loanAmount, margin);
        (IService.Loan[] memory loan, IService.Collateral[] memory collaterals, uint256 createdAt, ) = service
            .getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, IService.Status.OPEN);

        service.close(0, abi.encode(uint256(1)));
        _equalityWithTolerance(
            weth.balanceOf(address(this)),
            initial + mockRouter.amount() + service.quote(agreement)[0] - loan[0].amount,
            1
        );
    }

    function testGmxIntegrationUsdc(uint256 loanAmount, uint256 margin) public {
        margin = (margin % 9e7) + 1e8;
        uint256 initial = usdc.balanceOf(address(this)) - margin;
        _openGmxUsdc(loanAmount, margin);

        (IService.Loan[] memory loan, IService.Collateral[] memory collaterals, uint256 createdAt, ) = service
            .getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, IService.Status.OPEN);

        service.close(0, abi.encode(uint256(1)));
        _equalityWithTolerance(
            usdc.balanceOf(address(this)),
            initial + service.quote(agreement)[0] - loan[0].amount,
            1
        );
    }

    // setting to private since it becomes too heavy
    function testHeavyTesting(uint256 loanAmount, uint256 margin, uint256 seed) private {
        margin = (((margin % 1e17) + (seed % 987654321)) % 1e17) + 1e16;
        _openGmxEth(loanAmount, margin);
        margin = (((margin % 1e17) + (seed % 123456789)) % 1e17) + 1e16;
        _openGmxEth(loanAmount, margin);
        margin = (((margin % 1e17) + (seed % 345678901)) % 1e17) + 1e16;
        _openGmxEth(loanAmount, margin);
        service.close(1, abi.encode(uint256(1)));
        margin = (((margin % 1e17) + (seed % 514614341)) % 1e17) + 1e16;
        _openGmxEth(loanAmount, margin);
        margin = (((margin % 1e17) + (seed % 514614341)) % 1e17) + 1e16;
        service.close(0, abi.encode(uint256(1)));
        _openGmxEth(loanAmount, margin);
        service.close(4, abi.encode(uint256(1)));
        service.close(2, abi.encode(uint256(1)));
    }
}
