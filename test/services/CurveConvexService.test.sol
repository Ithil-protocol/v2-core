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
import { CurveConvexService } from "../../src/services/examples/CurveConvexService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract CurveConvexServiceTest is PRBTest, StdCheats, BaseServiceTest {
    IManager internal immutable manager;
    CurveConvexService internal immutable service;

    address internal constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // OHM-WETH
    address internal constant curvePool = 0x98a7F18d4E56Cfe84E3D081B40001B3d5bD3eB8B;
    address internal constant curveLpToken = 0x3D229E1B4faab62F621eF2F6A610961f7BD7b23B;
    uint256 internal constant convexPid = 54;

    IERC20 internal constant eurs = IERC20(0xdB25f211AB05b1c97D595516F45794528a807ad8);
    address internal constant eursWhale = 0xdB25f211AB05b1c97D595516F45794528a807ad8;
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant usdcWhale = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;

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
        eurs.approve(address(service), type(uint256).max);
        usdc.approve(address(service), type(uint256).max);

        vm.deal(eursWhale, 1 ether);
        vm.deal(usdcWhale, 1 ether);

        vm.startPrank(admin);
        manager.create(address(eurs));
        manager.create(address(usdc));
        manager.setCap(address(service), address(eurs), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(eurs);

        service.addPool(curvePool, convexPid, tokens, new address[](0));
        vm.stopPrank();
    }

    function testCurveConvexIntegration() public {
        uint256 eursAmount = 100 * 1e2;
        uint256 eursLoan = 10 * 1e2;
        uint256 eursMargin = 1 * 1e2;

        uint256 usdcAmount = 110 * 1e6;
        uint256 usdcLoan = 11 * 1e6;
        uint256 usdcMargin = 2 * 1e6;

        // Fill OHM vault
        IVault eursVault = IVault(manager.vaults(address(eurs)));
        vm.startPrank(eursWhale);
        eurs.transfer(address(this), eursMargin);
        eurs.approve(address(eursVault), eursAmount);
        eursVault.deposit(eursAmount, eursWhale);
        vm.stopPrank();

        // Fill WETH vault
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcMargin);
        usdc.approve(address(usdcVault), usdcAmount);
        usdcVault.deposit(usdcAmount, usdcWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(eurs);
        tokens[1] = address(usdc);

        uint256[] memory loans = new uint256[](2);
        loans[0] = eursLoan;
        loans[1] = usdcLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = eursMargin;
        margins[1] = usdcMargin;

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
