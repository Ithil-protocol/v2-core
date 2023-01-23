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
import { StargateService } from "../../src/services/examples/StargateService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract StargateServiceTest is PRBTest, StdCheats, BaseServiceTest {
    IManager internal immutable manager;
    StargateService internal immutable service;
    address internal constant stargate = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant usdcWhale = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant lpToken = 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56;
    uint16 internal constant usdcPoolID = 1;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16448665);
        vm.selectFork(forkId);

        manager = IManager(new Manager());
        service = new StargateService(address(manager), stargate);
    }

    function setUp() public {
        vm.startPrank(user);
        usdc.approve(address(service), type(uint256).max);
        vm.stopPrank();
        vm.deal(usdcWhale, 1 ether);

        manager.create(address(usdc));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION);
        service.addPool(address(usdc), 1);
    }

    function testStargateOpen() public {
        //vm.assume(amount < usdc.balanceOf(usdcWhale));
        //vm.assume(margin < amount);
        uint256 amount = 10 * 1e6;
        uint256 loan = 9 * 1e6;
        uint256 margin = 1e6;
        uint256 collateral = 9 * 1e6;

        IVault vault = IVault(manager.vaults(address(usdc)));
        vm.startPrank(usdcWhale);
        usdc.transfer(user, margin);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, usdcWhale);
        vm.stopPrank();

        IService.Order memory order = Helper.createSimpleERC20Order(
            address(usdc),
            loan,
            margin,
            lpToken,
            collateral,
            block.timestamp
        );

        vm.prank(user);
        service.open(order);

        assertTrue(service.id() == 1);

        (
            IService.Loan[] memory loans,
            IService.Collateral[] memory collaterals,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);
        assertTrue(loans.length == 1);
        assertTrue(collaterals.length == 1);
        assertTrue(createdAt == block.timestamp);
        assertTrue(status == IService.Status.OPEN);
    }
}
