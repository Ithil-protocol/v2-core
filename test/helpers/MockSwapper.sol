// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Swapper } from "../../src/swappers/Swapper.sol";

contract MockSwapper is Swapper {
    function swap(address from, address to, uint256 amount, uint256 minOut, bytes calldata data) external override {}
}
