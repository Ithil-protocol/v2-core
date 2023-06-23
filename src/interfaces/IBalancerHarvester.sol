// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

interface IBalancerHarvester {
    function harvest(address gauge, address[] memory tokens) external;
}
