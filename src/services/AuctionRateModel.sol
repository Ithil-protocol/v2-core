// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

contract AuctionRateModel is IInterestRateModel {
    // IR = baseIR + spread
    // Rate model in which baseIR is based on a Dutch auction
    // RESOLUTION corresponds to 1, i.e. an interest rate of 100%
    using GeneralMath for uint256;
    uint256 private constant RESOLUTION = 1e18;
    uint256 private constant HALVING_TIME = 1 weeks;

    // gas save: latest is a timestamp and base < RESOLUTION
    // thus they all fit in uint256
    // baseAndLatest = timestamp * 2^128 + base
    mapping(address => uint256) public baseAndLatest;

    function initializeIR(uint256 initialRate, uint256 firstTimestamp) external override {
        require(initialRate < RESOLUTION && firstTimestamp < RESOLUTION, "Invalid reset IR");
        baseAndLatest[msg.sender] = initialRate + (firstTimestamp << 128);
    }

    // throws if block.timestamp is smaller than latestBorrow
    // throws if amount >= freeLiquidity
    // throws if spread > type(uint256).max - newBase
    function computeInterestRate(uint256 amount, uint256 freeLiquidity) external override returns (uint256) {
        uint256 bal = baseAndLatest[msg.sender];
        uint256 latestBorrow = bal >> 128;
        uint256 blockTimestamp = block.timestamp;
        // Increase base due to new borrow
        uint256 newBase = (bal % (1 << 128)).safeMulDiv(freeLiquidity, freeLiquidity - amount);
        require(newBase < RESOLUTION, "Interest rate overflow");
        // Apply time based discount: after HALVING_TIME it is divided by 2
        newBase = newBase.safeMulDiv(HALVING_TIME, blockTimestamp - latestBorrow + HALVING_TIME);
        // Reset new base and latest borrow
        _resetIR(newBase, blockTimestamp);
        return newBase;
    }

    // internal function saves gas not to make resetIR public and conserves msg.sender
    function _resetIR(uint256 newBase, uint256 latestBorrow) internal {
        require(newBase < RESOLUTION, "Invalid reset IR");
        baseAndLatest[msg.sender] = newBase + (latestBorrow << 128);
    }
}
