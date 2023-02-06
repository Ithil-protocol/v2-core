// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { Service, IService } from "../../src/services/Service.sol";
import { WhitelistedService } from "../../src/services/WhitelistedService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract TestService is WhitelistedService {
    constructor(address manager) Service("TestService", "TEST-SERVICE", manager) {}

    function _open(Agreement memory agreement, bytes calldata data) internal override {}

    function edit(uint256 tokenID, Agreement calldata agreement, bytes calldata data) public override {}

    function _close(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal override {}
}

contract WhitelistedServiceTest is PRBTest, StdCheats, BaseServiceTest {
    using SafeERC20 for IERC20;

    IManager internal immutable manager;
    TestService internal immutable service;
    ERC20PresetMinterPauser internal immutable token;
    address internal constant whitelistedUser = address(uint160(uint(keccak256(abi.encodePacked("Whitelisted")))));
    uint256 internal constant collateral = 1e18;
    uint256 internal constant loan = 10 * 1e18;
    uint256 internal constant margin = 1e18;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new TestService(address(manager));
        vm.stopPrank();
    }

    function setUp() public {
        token.mint(whitelistedUser, type(uint128).max);
        token.mint(address(this), type(uint128).max);

        vm.prank(whitelistedUser);
        token.approve(address(service), type(uint256).max);
        token.approve(address(service), type(uint256).max);

        vm.startPrank(admin);
        manager.create(address(token));
        manager.setCap(address(service), address(token), GeneralMath.RESOLUTION);
        vm.stopPrank();
    }

    function testWhitelist() public {
        IService.Order memory order = Helper.createSimpleERC20Order(
            address(token),
            loan,
            margin,
            address(token),
            collateral
        );

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("UserIsNotWhitelisted()"))));
        service.open(order);

        vm.prank(admin);
        service.addToWhitelist(whitelistedUser);

        vm.prank(whitelistedUser);
        service.open(order);

        vm.prank(admin);
        service.removeFromWhitelist(whitelistedUser);

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("UserIsNotWhitelisted()"))));
        service.open(order);
    }
}