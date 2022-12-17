// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

interface IInterestRateModel {
    function initializeIR(uint256 initialRate) external;

    function computeInterestRate(uint256 amount, uint256 freeLiquidity) external returns (uint256);
}
