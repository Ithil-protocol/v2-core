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
import { SushiService } from "../../src/services/examples/SushiService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract SushiServiceTest is PRBTest, StdCheats, BaseServiceTest {
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

    function testSushiIntegration() public {
        //vm.assume(amount < dai.balanceOf(daiWhale));
        //vm.assume(margin < amount);
        uint256 usdcAmount = 4134 * 1e6;
        uint256 usdcLoan = 514 * 1e6;
        uint256 usdcMargin = 131 * 1e6;

        uint256 wethAmount = 135 * 1e18;
        uint256 wethLoan = 11 * 1e18;
        uint256 wethMargin = 3 * 1e18;

        // Fill USDC vault
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

        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[0] = 1;
        amountsOut[1] = 1;

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            abi.encode(amountsOut)
        );
        service.open(order);
    }
}
