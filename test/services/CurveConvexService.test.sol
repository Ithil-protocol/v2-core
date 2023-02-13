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

contract CurveConvexServiceTestRenBTCWBTC is BaseIntegrationServiceTest {
    IManager internal immutable manager;
    CurveConvexService internal immutable service;

    address internal constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // OHM-wbtc
    address internal constant curvePool = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
    address internal constant curveLpToken = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
    uint256 internal constant convexPid = 6;

    IERC20 internal constant renBTC = IERC20(0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D);
    address internal constant renBTCWhale = 0xaAde032DC41DbE499deBf54CFEe86d13358E9aFC;
    IERC20 internal constant wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address internal constant wbtcWhale = 0x218B95BE3ed99141b0144Dba6cE88807c4AD7C09;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16448665);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new CurveConvexService(address(manager), convexBooster, cvx);
        vm.stopPrank();
    }

    function setUp() public {
        renBTC.approve(address(service), type(uint256).max);
        wbtc.approve(address(service), type(uint256).max);

        vm.deal(renBTCWhale, 1 ether);
        vm.deal(wbtcWhale, 1 ether);

        vm.startPrank(admin);
        manager.create(address(renBTC));
        manager.create(address(wbtc));
        manager.setCap(address(service), address(renBTC), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(wbtc), GeneralMath.RESOLUTION);

        address[] memory tokens = new address[](2);
        tokens[0] = address(renBTC);
        tokens[1] = address(wbtc);

        service.addPool(curvePool, convexPid, tokens, new address[](0));
        vm.stopPrank();
    }

    function _prepareVaultsAndUser(
        uint256 renBTCAmount,
        uint256 renBTCMargin,
        uint256 wbtcAmount,
        uint256 wbtcMargin
    ) internal returns (uint256, uint256, uint256, uint256) {
        // Modifications to be sure renBTCAmount + renBTCMargin <= renBTC.balanceOf(renBTCWhale) and same for wbtc
        renBTCAmount = renBTCAmount % renBTC.balanceOf(renBTCWhale);
        renBTCMargin = renBTCMargin % (renBTC.balanceOf(renBTCWhale) - renBTCAmount);
        wbtcAmount = wbtcAmount % wbtc.balanceOf(wbtcWhale);
        wbtcMargin = wbtcMargin % (wbtc.balanceOf(wbtcWhale) - wbtcAmount);

        // add_liquidity() of the curve pool gives an EVM error when depositing 0
        // we enforce the amount to be at least 1

        renBTCAmount++;
        wbtcAmount++;
        renBTCMargin++;
        wbtcMargin++;

        // Fill renBTC vault
        IVault renBTCVault = IVault(manager.vaults(address(renBTC)));
        vm.startPrank(renBTCWhale);
        renBTC.transfer(address(this), renBTCMargin);
        renBTC.approve(address(renBTCVault), renBTCAmount);
        renBTCVault.deposit(renBTCAmount, renBTCWhale);
        vm.stopPrank();

        // Fill wbtc vault
        IVault wbtcVault = IVault(manager.vaults(address(wbtc)));
        vm.startPrank(wbtcWhale);
        wbtc.transfer(address(this), wbtcMargin);
        wbtc.approve(address(wbtcVault), wbtcAmount);
        wbtcVault.deposit(wbtcAmount, wbtcWhale);
        vm.stopPrank();
        return (renBTCAmount, renBTCMargin, wbtcAmount, wbtcMargin);
    }

    function _createOrder(
        uint256 renBTCLoan,
        uint256 renBTCMargin,
        uint256 wbtcLoan,
        uint256 wbtcMargin
    ) internal returns (IService.Order memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = address(renBTC);
        tokens[1] = address(wbtc);

        uint256[] memory loans = new uint256[](2);
        loans[0] = renBTCLoan;
        loans[1] = wbtcLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = renBTCMargin;
        margins[1] = wbtcMargin;

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
        uint256 renBTCAmount,
        uint256 renBTCLoan,
        uint256 renBTCMargin,
        uint256 wbtcAmount,
        uint256 wbtcLoan,
        uint256 wbtcMargin
    ) internal returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (renBTCAmount, renBTCMargin, wbtcAmount, wbtcMargin) = _prepareVaultsAndUser(
            renBTCAmount,
            renBTCMargin,
            wbtcAmount,
            wbtcMargin
        );
        // Loan must be less than amount otherwise Vault will revert
        // Since renBTCAmount > 0 and wbtcAmount > 0, the following does not revert for division by zero
        renBTCLoan = renBTCLoan % renBTCAmount;
        wbtcLoan = wbtcLoan % wbtcAmount;
        IService.Order memory order = _createOrder(renBTCLoan, renBTCMargin, wbtcLoan, wbtcMargin);

        service.open(order);
        return (renBTCAmount, renBTCLoan, renBTCMargin, wbtcAmount, wbtcLoan, wbtcMargin);
    }

    function testOpen(
        uint256 renBTCAmount,
        uint256 renBTCLoan,
        uint256 renBTCMargin,
        uint256 wbtcAmount,
        uint256 wbtcLoan,
        uint256 wbtcMargin
    ) public {
        uint256 timestamp = block.timestamp;
        (renBTCAmount, renBTCLoan, renBTCMargin, wbtcAmount, wbtcLoan, wbtcMargin) = _openOrder(
            renBTCAmount,
            renBTCLoan,
            renBTCMargin,
            wbtcAmount,
            wbtcLoan,
            wbtcMargin
        );

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        assertTrue(loan[0].token == address(renBTC));
        assertTrue(loan[0].amount == renBTCLoan);
        assertTrue(loan[0].margin == renBTCMargin);
        assertTrue(loan[1].token == address(wbtc));
        assertTrue(loan[1].amount == wbtcLoan);
        assertTrue(loan[1].margin == wbtcMargin);
        assertTrue(collateral[0].token == curveLpToken);
        assertTrue(collateral[0].identifier == 0);
        assertTrue(collateral[0].itemType == IService.ItemType.ERC20);
        assertTrue(createdAt == timestamp);
        assertTrue(status == IService.Status.OPEN);
    }

    function testClose(
        uint256 renBTCAmount,
        uint256 renBTCLoan,
        uint256 renBTCMargin,
        uint256 wbtcAmount,
        uint256 wbtcLoan,
        uint256 wbtcMargin,
        uint256 minAmountsOutrenBTC,
        uint256 minAmountsOutwbtc
    ) public {
        // (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        // vm.assume(minAmountsOutrenBTC <= totalBalances[0]);
        // vm.assume(minAmountsOutwbtc <= totalBalances[1]);
        (renBTCAmount, renBTCLoan, renBTCMargin, wbtcAmount, wbtcLoan, wbtcMargin) = _openOrder(
            renBTCAmount,
            renBTCLoan,
            renBTCMargin,
            wbtcAmount,
            wbtcLoan,
            wbtcMargin
        );

        // Allow for any loss
        // TODO: insert minAmountsOut and use quoter to check for slippage
        uint256[2] memory minAmountsOut = [uint256(0), uint256(0)];
        bytes memory data = abi.encode(minAmountsOut);

        service.close(0, data);
    }

    function testQuote(
        uint256 renBTCAmount,
        uint256 renBTCLoan,
        uint256 renBTCMargin,
        uint256 wbtcAmount,
        uint256 wbtcLoan,
        uint256 wbtcMargin
    ) public {
        (renBTCAmount, renBTCMargin, wbtcAmount, wbtcMargin) = _prepareVaultsAndUser(
            renBTCAmount,
            renBTCMargin,
            wbtcAmount,
            wbtcMargin
        );
        renBTCLoan = renBTCLoan % renBTCAmount;
        wbtcLoan = wbtcLoan % wbtcAmount;
        IService.Order memory order = _createOrder(renBTCLoan, renBTCMargin, wbtcLoan, wbtcMargin);

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
        uint256 renBTCAmount = 11 * 1e8;
        uint256 renBTCLoan = 1 * 1e8;
        uint256 renBTCMargin = 0.1 * 1e8;

        uint256 wbtcAmount = 11 * 1e8;
        uint256 wbtcLoan = 1 * 1e8;
        uint256 wbtcMargin = 0.1 * 1e8;

        // Fill OHM vault
        IVault renBTCVault = IVault(manager.vaults(address(renBTC)));
        vm.startPrank(renBTCWhale);
        renBTC.transfer(address(this), renBTCMargin);
        renBTC.approve(address(renBTCVault), renBTCAmount);
        renBTCVault.deposit(renBTCAmount, renBTCWhale);
        vm.stopPrank();

        // Fill wbtc vault
        IVault wbtcVault = IVault(manager.vaults(address(wbtc)));
        vm.startPrank(wbtcWhale);
        wbtc.transfer(address(this), wbtcMargin);
        wbtc.approve(address(wbtcVault), wbtcAmount);
        wbtcVault.deposit(wbtcAmount, wbtcWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(renBTC);
        tokens[1] = address(wbtc);

        uint256[] memory loans = new uint256[](2);
        loans[0] = renBTCLoan;
        loans[1] = wbtcLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = renBTCMargin;
        margins[1] = wbtcMargin;

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

        uint256[2] memory amounts = [uint256(100), uint256(1e6)];
        service.close(0, abi.encode(amounts));
    }
}
