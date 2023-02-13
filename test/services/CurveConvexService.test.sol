// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { CurveConvexService } from "../../src/services/debit/CurveConvexService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";

contract CurveConvexServiceTest is BaseIntegrationServiceTest {
    IManager internal immutable manager;
    CurveConvexService internal immutable service;

    address internal constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant crv = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
    address internal constant cvx = 0xb952A807345991BD529FDded05009F5e80Fe8F45;

    // OHM-usdt
    address internal constant curvePool = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address internal constant curveLpToken = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    uint256 internal constant convexPid = 1;

    IERC20 internal constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address internal constant usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    IERC20 internal constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address internal constant usdtWhale = 0x0D0707963952f2fBA59dD06f2b425ace40b492Fe;

    constructor() {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"), 55895589);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new CurveConvexService(address(manager), convexBooster, crv, cvx);
        vm.stopPrank();
    }

    function setUp() public {
        usdc.approve(address(service), type(uint256).max);
        usdt.approve(address(service), type(uint256).max);

        vm.deal(usdcWhale, 1 ether);
        vm.deal(usdtWhale, 1 ether);

        vm.startPrank(admin);
        manager.create(address(usdc));
        manager.create(address(usdt));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(usdt), GeneralMath.RESOLUTION);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);

        service.addPool(curvePool, convexPid, tokens, new address[](0));
        vm.stopPrank();
    }

    function _prepareVaultsAndUser(
        uint256 usdcAmount,
        uint256 usdcMargin,
        uint256 usdtAmount,
        uint256 usdtMargin
    ) internal returns (uint256, uint256, uint256, uint256) {
        // Modifications to be sure usdcAmount + usdcMargin <= usdc.balanceOf(usdcWhale) and same for usdt
        usdcAmount = usdcAmount % usdc.balanceOf(usdcWhale);
        usdcMargin = usdcMargin % (usdc.balanceOf(usdcWhale) - usdcAmount);
        usdtAmount = usdtAmount % usdt.balanceOf(usdtWhale);
        usdtMargin = usdtMargin % (usdt.balanceOf(usdtWhale) - usdtAmount);

        // add_liquidity() of the curve pool gives an EVM error when depositing 0
        // we enforce the amount to be at least 1

        usdcAmount++;
        usdtAmount++;
        usdcMargin++;
        usdtMargin++;

        // Fill usdc vault
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcMargin);
        usdc.approve(address(usdcVault), usdcAmount);
        usdcVault.deposit(usdcAmount, usdcWhale);
        vm.stopPrank();

        // Fill usdt vault
        IVault usdtVault = IVault(manager.vaults(address(usdt)));
        vm.startPrank(usdtWhale);
        usdt.transfer(address(this), usdtMargin);
        usdt.approve(address(usdtVault), usdtAmount);
        usdtVault.deposit(usdtAmount, usdtWhale);
        vm.stopPrank();
        return (usdcAmount, usdcMargin, usdtAmount, usdtMargin);
    }

    function _createOrder(
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 usdtLoan,
        uint256 usdtMargin
    ) internal returns (IService.Order memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);

        uint256[] memory loans = new uint256[](2);
        loans[0] = usdcLoan;
        loans[1] = usdtLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = usdcMargin;
        margins[1] = usdtMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = curveLpToken;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

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

    function _openOrder(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 usdtAmount,
        uint256 usdtLoan,
        uint256 usdtMargin
    ) internal returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (usdcAmount, usdcMargin, usdtAmount, usdtMargin) = _prepareVaultsAndUser(
            usdcAmount,
            usdcMargin,
            usdtAmount,
            usdtMargin
        );
        // Loan must be less than amount otherwise Vault will revert
        // Since usdcAmount > 0 and usdtAmount > 0, the following does not revert for division by zero
        usdcLoan = usdcLoan % usdcAmount;
        usdtLoan = usdtLoan % usdtAmount;
        IService.Order memory order = _createOrder(usdcLoan, usdcMargin, usdtLoan, usdtMargin);

        service.open(order);
        return (usdcAmount, usdcLoan, usdcMargin, usdtAmount, usdtLoan, usdtMargin);
    }

    function testCurveOpenPosition(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 usdtAmount,
        uint256 usdtLoan,
        uint256 usdtMargin
    ) public {
        uint256 timestamp = block.timestamp;
        (usdcAmount, usdcLoan, usdcMargin, usdtAmount, usdtLoan, usdtMargin) = _openOrder(
            usdcAmount,
            usdcLoan,
            usdcMargin,
            usdtAmount,
            usdtLoan,
            usdtMargin
        );

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        assertTrue(loan[0].token == address(usdc));
        assertTrue(loan[0].amount == usdcLoan);
        assertTrue(loan[0].margin == usdcMargin);
        assertTrue(loan[1].token == address(usdt));
        assertTrue(loan[1].amount == usdtLoan);
        assertTrue(loan[1].margin == usdtMargin);
        assertTrue(collateral[0].token == curveLpToken);
        assertTrue(collateral[0].identifier == 0);
        assertTrue(collateral[0].itemType == IService.ItemType.ERC20);
        assertTrue(createdAt == timestamp);
        assertTrue(status == IService.Status.OPEN);
    }

    function testCurveClosePosition(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 usdtAmount,
        uint256 usdtLoan,
        uint256 usdtMargin,
        uint256 minAmountsOutusdc,
        uint256 minAmountsOutusdt
    ) public {
        // (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        // vm.assume(minAmountsOutusdc <= totalBalances[0]);
        // vm.assume(minAmountsOutusdt <= totalBalances[1]);
        (usdcAmount, usdcLoan, usdcMargin, usdtAmount, usdtLoan, usdtMargin) = _openOrder(
            usdcAmount,
            usdcLoan,
            usdcMargin,
            usdtAmount,
            usdtLoan,
            usdtMargin
        );

        // Allow for any loss
        // TODO: insert minAmountsOut and use quoter to check for slippage
        uint256[2] memory minAmountsOut = [uint256(0), uint256(0)];
        bytes memory data = abi.encode(minAmountsOut);

        service.close(0, data);
    }

    function testCurveQuote(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 usdtAmount,
        uint256 usdtLoan,
        uint256 usdtMargin
    ) public {
        (usdcAmount, usdcMargin, usdtAmount, usdtMargin) = _prepareVaultsAndUser(
            usdcAmount,
            usdcMargin,
            usdtAmount,
            usdtMargin
        );
        usdcLoan = usdcLoan % usdcAmount;
        usdtLoan = usdtLoan % usdtAmount;
        IService.Order memory order = _createOrder(usdcLoan, usdcMargin, usdtLoan, usdtMargin);

        service.open(order);

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        (uint256[] memory quoted, ) = service.quote(agreement);
    }

    function testCurveConvexIntegration() public {
        uint256 usdcAmount = 11 * 1e6;
        uint256 usdcLoan = 1 * 1e6;
        uint256 usdcMargin = 0.1 * 1e6;

        uint256 usdtAmount = 11 * 1e6;
        uint256 usdtLoan = 1 * 1e6;
        uint256 usdtMargin = 0.1 * 1e6;

        // Fill OHM vault
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcMargin);
        usdc.approve(address(usdcVault), usdcAmount);
        usdcVault.deposit(usdcAmount, usdcWhale);
        vm.stopPrank();

        // Fill usdt vault
        IVault usdtVault = IVault(manager.vaults(address(usdt)));
        vm.startPrank(usdtWhale);
        usdt.transfer(address(this), usdtMargin);
        usdt.approve(address(usdtVault), usdtAmount);
        usdtVault.deposit(usdtAmount, usdtWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);

        uint256[] memory loans = new uint256[](2);
        loans[0] = usdcLoan;
        loans[1] = usdtLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = usdcMargin;
        margins[1] = usdtMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = curveLpToken;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

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

        service.open(order);

        uint256[2] memory amounts = [uint256(1e6), uint256(1e6)];
        service.close(0, abi.encode(amounts));
    }
}
