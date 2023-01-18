// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { YearnService } from "../../src/services/examples/YearnService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";

contract YearnServiceTest is PRBTest, StdCheats {
    Manager internal immutable manager;
    YearnService internal immutable service;
    address internal constant registry = 0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804;
    IERC20 internal constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address internal constant daiWhale = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16433647);
        vm.selectFork(forkId);

        manager = new Manager();
        service = new YearnService(address(manager), registry);
    }

    function setUp() public {
        dai.approve(address(service), type(uint256).max);
        vm.deal(daiWhale, 1 ether);
    }

    function testStake(uint256 amount) public {
        vm.assume(amount < dai.balanceOf(daiWhale));

        vm.prank(daiWhale);
        dai.transfer(address(this), amount);

        IService.Loan[] memory loan = new IService.Loan[](1);
        IService.Collateral[] memory collateral = new IService.Collateral[](1);
        IService.Agreement memory agreement = IService.Agreement({
            loans: loan,
            collaterals: collateral,
            createdAt: block.timestamp,
            status: IService.Status.OPEN 
        });
        IService.Order memory order = IService.Order({
            agreement: agreement,
            data: ""
        });

        service.open(order);
    }
}
