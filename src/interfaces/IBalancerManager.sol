// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IService } from "./IService.sol";

interface IBalancerManager {
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

    function harvest(address gauge, address[] memory tokens) external;

    function quote(IService.Agreement memory agreement, PoolData memory pool) external view returns (uint256[] memory);

    function getPool(address) external view returns (PoolData memory);
}
