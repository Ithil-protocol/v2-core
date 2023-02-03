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

        // Fill WETH vault
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
