// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { ISwapper } from "../interfaces/ISwapper.sol";

abstract contract Swapper is ISwapper {
    function swap(address from, address to, uint256 amount, uint256 minOut, bytes calldata data)
        external
        virtual
        override;
}
