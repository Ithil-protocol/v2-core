// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

// IR = baseIR + spread
// Rate model in which baseIR is based on a Dutch auction
// GeneralMath.RESOLUTION corresponds to 1, i.e. an interest rate of 100%
contract AuctionRateModel is IInterestRateModel {
    using GeneralMath for uint256;

    error InvalidParams();

    // gas save: latest is a timestamp and base < GeneralMath.RESOLUTION
    // thus they all fit in uint256
    // baseAndLatest = timestamp * 2^128 + base
    mapping(address => uint256) internal baseAndLatest;
    uint256 private constant HALVING_TIME = 1 weeks;

    function initializeIR(uint256 initialRate, uint256 firstTimestamp) external override {
        if (initialRate > GeneralMath.RESOLUTION || firstTimestamp > GeneralMath.RESOLUTION) revert InvalidParams();

        baseAndLatest[msg.sender] = initialRate + (firstTimestamp << 128);
    }

    // throws if block.timestamp is smaller than latestBorrow
    // throws if amount >= freeLiquidity
    // throws if spread > type(uint256).max - newBase
    function computeInterestRate(uint256 amount, uint256 freeLiquidity) external override returns (uint256) {
        uint256 bal = baseAndLatest[msg.sender];
        uint256 latestBorrow = bal >> 128;
        // Increase base due to new borrow
        uint256 newBase = (bal % (1 << 128)).safeMulDiv(freeLiquidity, freeLiquidity - amount);
        assert(newBase < GeneralMath.RESOLUTION); // Interest rate overflow
        // Apply time based discount: after HALVING_TIME it is divided by 2
        newBase = newBase.safeMulDiv(HALVING_TIME, block.timestamp - latestBorrow + HALVING_TIME);
        // Reset new base and latest borrow
        assert(newBase < GeneralMath.RESOLUTION); // Interest rate overflow
        baseAndLatest[msg.sender] = newBase + (latestBorrow << 128);

        return newBase;
    }
}
