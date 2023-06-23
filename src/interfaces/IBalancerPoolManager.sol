// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

interface IBalancerPoolManager {
    struct PoolData {
        bytes32 balancerPoolID;
        address[] tokens;
        uint256[] weights;
        uint256[] scalingFactors;
        uint256 maximumWeightIndex;
        uint8 length;
        uint256 swapFee;
        address gauge;
        address protocolFeeCollector;
    }

    event PoolWasAdded(address indexed balancerPool);
    event PoolWasRemoved(address indexed balancerPool);

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external;

    function removePool(address poolAddress) external;
}
