// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ISwapper, Swapper } from "../src/Swapper.sol";

contract SwapperTest is Test {
    Swapper internal immutable swapper;
    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 58581858;

    // dexes
    address internal constant sushirouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    // tokens
    IERC20 internal constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    address internal constant gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        swapper = new Swapper();
    }

    function setUp() public {
        vm.deal(gmxVault, 1 ether);
    }

    function testSwapWethToUsdcOnSushi(uint256 amount) public {
        amount = bound(amount, 1e6, usdc.balanceOf(gmxVault)); // there is a min amount to perform a swap

        vm.prank(gmxVault);
        usdc.transfer(address(swapper), amount);

        swapper.changeDexRouter(ISwapper.Dex.SUSHI, sushirouter);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        ISwapper.SwapData memory data = ISwapper.SwapData(ISwapper.Dex.SUSHI, path, 10, "");
        swapper.changeSwapPath(address(usdc), address(weth), data);

        assertTrue(usdc.balanceOf(address(swapper)) == amount);
        assertTrue(usdc.balanceOf(address(this)) == 0);
        assertTrue(weth.balanceOf(address(swapper)) == 0);
        assertTrue(weth.balanceOf(address(this)) == 0);
        swapper.swap(address(usdc), address(weth), amount, 1);
        assertTrue(usdc.balanceOf(address(swapper)) == 0);
        assertTrue(usdc.balanceOf(address(this)) == 0);
        assertTrue(weth.balanceOf(address(swapper)) == 0);
        assertTrue(weth.balanceOf(address(this)) > 0);

        console2.log(weth.balanceOf(address(this)));
    }
}
