// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { Oracle } from "../src/Oracle.sol";

contract OracleTest is Test {
    Oracle internal immutable oracle;

    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal constant ethFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant usdcFeed = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);

        oracle = new Oracle();
    }

    function testOracle() public {
        /*
            ETH/USD
            answer   int256 :  164416000000

            USDC/USD
            answer   int256 :  99995000
        */

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("TokenNotSupported()"))));
        oracle.getPrice(weth, usdc, 1);

        oracle.setPriceFeed(weth, ethFeed);
        oracle.setPriceFeed(usdc, usdcFeed);

        uint256 price = oracle.getPrice(weth, usdc, 8);
        price /= 1e8;

        assertTrue(price > 1820 && price < 1830);
    }
}
