// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { IAugustusSwapper } from "../../src/interfaces/external/paraswap/IAugustusSwapper.sol";
import { ParaSwap } from "../../src/swappers/ParaSwap.sol";
import { StringUtils } from "../utils/StringUtils.sol";

contract ParaSwapTest is Test {
    ParaSwap internal immutable swapper;

    address internal constant router = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
    address internal constant proxy = 0x216B4B4Ba9F3e719726886d34a177484278Bfcae;
    IERC20 internal constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant whale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 65696886;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);

        swapper = new ParaSwap(router, proxy);
    }

    function setUp() public {
        vm.deal(whale, 1 ether);
    }

    function testParaSwap() public {
        uint256 amount = 1000000;

        address[] memory callees = new address[](2);
        callees[0] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        callees[1] = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

        uint256[] memory startIndexes = new uint256[](3);
        startIndexes[0] = 0;
        startIndexes[1] = 292;
        startIndexes[2] = 328;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        // solhint-disable max-line-length
        IAugustusSwapper.SimpleData memory data = IAugustusSwapper.SimpleData({
            fromToken: address(usdc),
            toToken: address(weth),
            fromAmount: 1000000,
            toAmount: 604219092872398,
            expectedAmount: 604823916789187,
            callees: callees,
            exchangeData: StringUtils.fromHex(
                "c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000def171fe48cf0115b1d80b88dc8eab59176fee570000000000000000000000000000000000000000000000000000000063ff2d5200000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bff970a61a04b1ca14834a43f5de4533ebddb5cc80001f482af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000e1829cfe00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1"
            ),
            startIndexes: startIndexes,
            values: values,
            beneficiary: payable(0x0000000000000000000000000000000000000000),
            partner: payable(0x08a3c2A819E3de7ACa384c798269B3Ce1CD0e437),
            feePercent: 452312848583266388373324160190187140051835877600158453279131187530910662656,
            permit: "0x",
            deadline: 1677685667,
            uuid: bytes16(bytes("0x1396a2ac833c43e591d831708670f600"))
        });
        // solhint-enable max-line-length

        vm.startPrank(whale);
        usdc.approve(address(swapper), amount);
        swapper.swap(address(usdc), address(weth), amount, 1, abi.encode(data));
        vm.stopPrank();
    }
}
