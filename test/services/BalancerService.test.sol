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
import { BalancerService } from "../../src/services/examples/BalancerService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract BalancerServiceTest is PRBTest, StdCheats, BaseServiceTest {
    IManager internal immutable manager;
    BalancerService internal immutable service;
    IERC20 internal constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    // Block 16448665 dai whale balance = 193908563885609559262031126 > 193908563 * 10^18
    address internal constant daiWhale = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    IERC20 internal constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // Block 16448665 weth whale balance = 13813826751282430350873 > 13813 * 10
    address internal constant wethWhale = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
    address internal constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // address internal constant auraBooster = 0x7818A1DA7BD1E64c199029E86Ba244a9798eEE10;
    // Pool 60 WETH - 40 DAI
    address internal constant balancerPoolAddress = 0x0b09deA16768f0799065C475bE02919503cB2a35;
    bytes32 internal constant balancerPoolID = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    address internal constant gauge = 0x4ca6AC0509E6381Ca7CD872a6cdC0Fbf00600Fa1;
    address internal constant bal = 0xba100000625a3754423978a60c9317c58a424e3D;

    // address internal constant auraPoolID = 2;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16448665);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new BalancerService(address(manager), balancerVault, bal);
        vm.stopPrank();
    }

    function setUp() public {
        dai.approve(address(service), type(uint256).max);
        weth.approve(address(service), type(uint256).max);

        vm.deal(daiWhale, 1 ether);
        vm.deal(wethWhale, 1 ether);

        vm.startPrank(admin);
        // Create Vaults: DAI and WETH
        manager.create(address(dai));
        manager.create(address(weth));
        // No caps for this service -> 100% of the liquidity can be used initially
        manager.setCap(address(service), address(dai), GeneralMath.RESOLUTION);
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION);

        service.addPool(balancerPoolAddress, balancerPoolID, gauge);
        vm.stopPrank();
    }

    function testBalancerIntegration() public {
        //vm.assume(amount < dai.balanceOf(daiWhale));
        //vm.assume(margin < amount);
        uint256 daiAmount = 4134 * 1e18;
        uint256 daiLoan = 514 * 1e18;
        uint256 daiMargin = 131 * 1e18;

        uint256 wethAmount = 135 * 1e18;
        uint256 wethLoan = 11 * 1e18;
        uint256 wethMargin = 3 * 1e18;

        // Fill DAI vault
        IVault daiVault = IVault(manager.vaults(address(dai)));
        vm.startPrank(daiWhale);
        dai.transfer(address(this), daiMargin);
        dai.approve(address(daiVault), daiAmount);
        daiVault.deposit(daiAmount, daiWhale);
        vm.stopPrank();

        // Fill WETH vault
        IVault wethVault = IVault(manager.vaults(address(weth)));
        vm.startPrank(wethWhale);
        weth.transfer(address(this), wethMargin);
        weth.approve(address(wethVault), wethAmount);
        wethVault.deposit(wethAmount, wethWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(weth);

        uint256[] memory loans = new uint256[](2);
        loans[0] = daiLoan;
        loans[1] = wethLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = daiMargin;
        margins[1] = wethMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = balancerPoolAddress;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp
        );

        service.open(order);

        /*
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 1;
            amounts[1] = 1;
            service.close(0, abi.encode(amounts));
        */
    }

    function testQuote() public {
        //vm.assume(amount < dai.balanceOf(daiWhale));
        //vm.assume(margin < amount);
        uint256 daiAmount = 4134 * 1e18;
        uint256 daiLoan = 514 * 1e18;
        uint256 daiMargin = 131 * 1e18;

        uint256 wethAmount = 135 * 1e18;
        uint256 wethLoan = 11 * 1e18;
        uint256 wethMargin = 3 * 1e18;

        // Fill DAI vault
        IVault daiVault = IVault(manager.vaults(address(dai)));
        vm.startPrank(daiWhale);
        dai.transfer(address(this), daiMargin);
        dai.approve(address(daiVault), daiAmount);
        daiVault.deposit(daiAmount, daiWhale);
        vm.stopPrank();

        // Fill WETH vault
        IVault wethVault = IVault(manager.vaults(address(weth)));
        vm.startPrank(wethWhale);
        weth.transfer(address(this), wethMargin);
        weth.approve(address(wethVault), wethAmount);
        wethVault.deposit(wethAmount, wethWhale);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(weth);

        uint256[] memory loans = new uint256[](2);
        loans[0] = daiLoan;
        loans[1] = wethLoan;

        uint256[] memory margins = new uint256[](2);
        margins[0] = daiMargin;
        margins[1] = wethMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = balancerPoolAddress;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp
        );

        service.open(order);

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Loan[] memory permutedLoan = new IService.Loan[](2);
        permutedLoan[0] = loan[1];
        permutedLoan[1] = loan[0];

        IService.Agreement memory agreement = IService.Agreement(permutedLoan, collateral, createdAt, status);

        (uint256[] memory quoted, uint256[] memory fees) = service.quote(agreement);
        assertTrue(quoted[0] >= permutedLoan[0].amount);
        assertTrue(quoted[1] >= permutedLoan[1].amount);
        // Interest rate not set for now
        assertTrue(fees[0] == 0);
        assertTrue(fees[1] == 0);
    }
}
