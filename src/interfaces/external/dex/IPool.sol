// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

interface IPool {
    function createOrder(uint256 amount, uint256 price, address recipient, uint256 deadline) external payable;
}
