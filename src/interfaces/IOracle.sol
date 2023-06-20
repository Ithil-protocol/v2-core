// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

interface IOracle {
    function getPrice(address from, address to, uint8 decimals) external view returns (uint256);
}
