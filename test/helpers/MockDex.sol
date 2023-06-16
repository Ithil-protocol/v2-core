// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IFactory } from "../../src/interfaces/external/dex/IFactory.sol";
import { IPool } from "../../src/interfaces/external/dex/IPool.sol";

contract MockDex is IFactory, IPool {
    function pools(address /*token0*/, address /*token1*/) external view override returns (address) {
        return address(this);
    }

    function createOrder(
        uint256 amount,
        uint256 price,
        address recipient,
        uint256 deadline
    ) external payable override {}
}
