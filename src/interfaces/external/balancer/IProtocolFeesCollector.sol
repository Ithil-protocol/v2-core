// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

/// @title    Interface of Balancer BasePool contract
interface IProtocolFeesCollector {
    /**
     * @dev Returns all normalised weights, in the same order as the Pool's tokens.
     */
    function getSwapFeePercentage() external view returns (uint256);
}
