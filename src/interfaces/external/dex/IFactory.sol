// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

interface IFactory {
    function pools(address token0, address token1) external view returns (address);
}
