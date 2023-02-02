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
    address internal constant curvePool = 0x6ec38b3228251a0C5D491Faf66858e2E23d7728B;
    address internal constant curveLpToken = 0x3660BD168494d61ffDac21E403d0F6356cF90fD7;
    uint256 internal constant convexPid = 92;
    IERC20 internal constant ohm = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    address internal constant ohmWhale = 0xB63cac384247597756545b500253ff8E607a8020;
    IERC20 internal constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant wethWhale = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;

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
        ohm.approve(address(service), type(uint256).max);
        weth.approve(address(service), type(uint256).max);

        vm.deal(ohmWhale, 1 ether);
        vm.deal(wethWhale, 1 ether);

        vm.startPrank(admin);
        manager.create(address(ohm));
        manager.create(address(weth));
        manager.setCap(address(service), address(ohm), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION);

        address[] memory tokens = new address[](2);
        tokens[0] = address(ohm);
        tokens[1] = address(weth);

        service.addPool(curvePool, convexPid, tokens);
        vm.stopPrank();
    }

    function testCurveConvexIntegration() public {
        uint256 ohmAmount = 4134 * 1e9;
        uint256 ohmLoan = 514 * 1e9;
        uint256 ohmMargin = 131 * 1e9;

        uint256 wethAmount = 135 * 1e18;
        uint256 wethLoan = 11 * 1e18;
        uint256 wethMargin = 3 * 1e18;

        // Fill OHM vault
        IVault ohmVault = IVault(manager.vaults(address(ohm)));
        vm.startPrank(ohmWhale);
        ohm.transfer(address(this), ohmMargin);
        ohm.approve(address(ohmVault), ohmAmount);
        ohmVault.deposit(ohmAmount, ohmWhale);
        vm.stopPrank();

        // Fill WETH vault
        IVault wethVault = IVault(manager.vaults(address(weth)));
        vm.startPrank(wethWhale);
        weth.transfer(address(this), wethMargin);
        weth.approve(address(wethVault), wethAmount);
        wethVault.deposit(wethAmount, wethWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(ohm);
        tokens[1] = address(weth);

        uint256[] memory loans = new uint256[](2);
        loans[0] = ohmLoan;
        loans[1] = wethLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = ohmMargin;
        margins[1] = wethMargin;

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

        uint256[2] memory amounts = [uint256(1e9), uint256(1e18)];
        service.close(0, abi.encode(amounts));
    }
}
