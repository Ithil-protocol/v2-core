// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Test } from "forge-std/Test.sol";
import { TokenVestor } from "../src/TokenVestor.sol";
import { Ithil } from "../src/Ithil.sol";

contract TokenVestorTest is Test {
    Ithil internal immutable token;
    TokenVestor internal immutable tokenVestor;
    address internal constant user1 = address(uint160(uint(keccak256(abi.encodePacked("User1")))));
    address internal constant user2 = address(uint160(uint(keccak256(abi.encodePacked("User2")))));

    constructor() {
        token = new Ithil();
        tokenVestor = new TokenVestor(address(token));
    }

    function setUp() public {
        token.approve(address(tokenVestor), type(uint256).max);
    }

    function testVestedtokensCannotBeTransferred() public {
        tokenVestor.addAllocation(1e18, block.timestamp, 30 days, user1);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("TransferNotSupported()"))));
        tokenVestor.transfer(address(0), 1);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("TransferNotSupported()"))));
        tokenVestor.transferFrom(user1, address(this), 1);
        vm.stopPrank();
    }

    function testNullAllocation() public {
        vm.prank(user1);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("NullAllocation()"))));
        tokenVestor.claim();
        assertTrue(tokenVestor.balanceOf(user1) == 0);
    }

    function testClaim(uint256 amount, uint256 start, uint256 duration) public {
        amount = bound(amount, 1e18, token.balanceOf(address(this)));
        start = bound(start, block.timestamp + 1 days, block.timestamp + 24 weeks);
        duration = bound(duration, 1 days, 144 weeks);

        tokenVestor.addAllocation(amount, start, duration, user1);

        vm.prank(user1);
        tokenVestor.claim();
        assertTrue(token.balanceOf(user1) == 0);

        vm.warp(start + 1 seconds);

        vm.prank(user1);
        tokenVestor.claim();
        assertTrue(token.balanceOf(user1) > 0);

        vm.warp(start + duration + 1 seconds);

        vm.prank(user1);
        tokenVestor.claim();
        assertTrue(token.balanceOf(user1) == amount);

        assertTrue(token.balanceOf(address(tokenVestor)) == 0);
    }
}
