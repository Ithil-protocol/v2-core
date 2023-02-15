// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { GmxService } from "../../src/services/debit/GmxService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";

contract GmxServiceTest is BaseIntegrationServiceTest {
    GmxService internal immutable service;
    address internal constant gmxRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant whale = 0x8b8149Dd385955DC1cE77a4bE7700CCD6a212e65;
    uint256 internal constant amount = 100 * 1e18;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 58581858;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.deal(admin, 1 ether);
        vm.deal(whale, 1 ether);

        vm.prank(admin);
        service = new GmxService(address(manager), gmxRouter);
    }

    function setUp() public override {
        weth.approve(address(service), type(uint256).max);

        vm.startPrank(admin);
        manager.create(address(weth));
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION);
        vm.stopPrank();

        vm.startPrank(whale);
        weth.transfer(address(this), 1e18);
        IVault vault = IVault(manager.vaults(address(weth)));
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(amount, whale);
        vm.stopPrank();
    }

    function testGmxIntegration() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);

        uint256[] memory loans = new uint256[](1);
        loans[0] = 10 * 1e18;

        uint256[] memory margins = new uint256[](1);
        margins[0] = 1e18;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

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

        service.open(order);
        service.quote(order.agreement);
        service.close(0, "");
    }
}
