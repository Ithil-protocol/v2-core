// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Test } from "forge-std/Test.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { Service, IService } from "../../src/services/Service.sol";
import { Whitelisted } from "../../src/services/Whitelisted.sol";
import { AuctionRateModel } from "../../src/irmodels/AuctionRateModel.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";

contract TestService is Whitelisted, AuctionRateModel, Service {
    constructor(address manager) Service("TestService", "TEST-SERVICE", manager, 30 * 86400) {}

    function _close(
        uint256 tokenID,
        IService.Agreement memory agreement,
        bytes memory data
    ) internal virtual override {}

    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual override onlyWhitelisted {}
}

contract WhitelistedTest is Test, IERC721Receiver {
    using SafeERC20 for IERC20;

    Manager internal immutable manager;
    TestService internal immutable service;
    ERC20PresetMinterPauser internal immutable token;
    address internal immutable admin = address(uint160(uint256(keccak256(abi.encodePacked("admin")))));
    address internal constant whitelistedUser = address(uint160(uint256(keccak256(abi.encodePacked("Whitelisted")))));
    address internal constant whitelistedUser2 = address(uint160(uint256(keccak256(abi.encodePacked("Whitelisted2")))));
    uint256 internal constant collateral = 1e18;
    uint256 internal constant loan = 10 * 1e18;
    uint256 internal constant margin = 1e18;

    constructor() {
        token = new ERC20PresetMinterPauser("test", "TEST");

        vm.startPrank(admin);
        manager = new Manager();
        service = new TestService(address(manager));
        vm.stopPrank();
    }

    function setUp() public {
        token.mint(whitelistedUser, type(uint128).max);
        token.mint(address(this), type(uint128).max);

        vm.prank(whitelistedUser);
        token.approve(address(service), type(uint256).max);

        vm.prank(whitelistedUser);
        token.transfer(admin, 1);
        vm.startPrank(admin);
        token.approve(address(manager), 1);
        manager.create(address(token));
        manager.setCap(address(service), address(token), GeneralMath.RESOLUTION, type(uint256).max);
        vm.stopPrank();
    }

    function testWhitelist() public {
        IService.Order memory order = OrderHelper.createSimpleERC20Order(
            address(token),
            loan,
            margin,
            address(token),
            collateral
        );

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("UserIsNotWhitelisted()"))));
        service.open(order);

        address[] memory whitelistedUsers = new address[](2);
        whitelistedUsers[0] = whitelistedUser;
        whitelistedUsers[1] = whitelistedUser2;

        vm.prank(admin);
        service.addToWhitelist(whitelistedUsers);

        vm.prank(whitelistedUser);
        service.open(order);

        vm.prank(whitelistedUser2);
        service.open(order);

        vm.prank(admin);
        service.removeFromWhitelist(whitelistedUsers);

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("UserIsNotWhitelisted()"))));
        vm.prank(whitelistedUser);
        service.open(order);

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("UserIsNotWhitelisted()"))));
        vm.prank(whitelistedUser2);
        service.open(order);

        vm.prank(admin);
        service.toggleWhitelistFlag();

        service.open(order);
        vm.prank(whitelistedUser);
        service.open(order);
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
