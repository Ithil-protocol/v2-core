// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Test } from "forge-std/Test.sol";
import { IService, Service } from "../src/services/Service.sol";

contract MockService is Service {
    constructor() Service("test", "TEST", address(0)) {}
}

contract ServiceTest is Test, IERC721Receiver {
    MockService internal immutable service;
    address internal immutable owner = address(uint160(uint(keccak256(abi.encodePacked("owner")))));
    address internal immutable guardian = address(uint160(uint(keccak256(abi.encodePacked("guardian")))));

    constructor() {
        vm.startPrank(owner);
        service = new MockService();
        service.setGuardian(guardian);
        vm.stopPrank();
    }

    function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/)
        external
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function testLocking() public {
        IService.Order memory order;
        service.open(order);

        vm.prank(guardian);
        service.suspend();

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Locked()"))));
        service.open(order);

        vm.prank(guardian);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        service.lock();

        vm.prank(owner);
        service.liftSuspension();

        service.open(order);

        vm.prank(owner);
        service.lock();

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Locked()"))));
        service.open(order);

        vm.prank(owner);
        vm.expectRevert();
        service.liftSuspension();
    }
}
