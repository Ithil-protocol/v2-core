// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { GeneralMath } from "../libraries/GeneralMath.sol";

/// @dev IR = baseIR + spread
/// Rate model in which baseIR is based on a Dutch auction
/// GeneralMath.RESOLUTION corresponds to 1, i.e. an interest rate of 100%
contract AuctionRateModel {
    using GeneralMath for uint256;

    /**
     * @dev gas saving trick
     * latest is a timestamp and base < GeneralMath.RESOLUTION, they all fit in uint256
     * baseAndLatest = timestamp * 2^128 + base
     */
    uint256 public baseAndLatest;
    uint256 public immutable halvingTime;

    constructor(uint256 _halvingTime, uint256 _initialRate) {
        assert(_initialRate < GeneralMath.RESOLUTION);
        assert(_halvingTime > 0);
        halvingTime = _halvingTime;
        baseAndLatest = GeneralMath.packInUint(block.timestamp, _initialRate);
    }

    /**
     * @dev calculating the end IR value
     * throws if block.timestamp is smaller than latestBorrow
     * throws if amount >= freeLiquidity
     * throws if spread > type(uint256).max - newBase
     */
    function computeInterestRate(uint256 amount, uint256 freeLiquidity) internal returns (uint256) {
        (uint256 latestBorrow, uint256 base) = GeneralMath.unpackUint(baseAndLatest);
        // Increase base due to new borrow and then
        // apply time based discount: after halvingTime it is divided by 2
        uint256 newBase = base.safeMulDiv(freeLiquidity, freeLiquidity - amount).safeMulDiv(
            halvingTime,
            block.timestamp - latestBorrow + halvingTime
        );
        // Reset new base and latest borrow, force IR stays below resolution
        if (newBase >= GeneralMath.RESOLUTION) revert Interest_Rate_Overflow();
        baseAndLatest = GeneralMath.packInUint(block.timestamp, newBase);

        return newBase;
    }

    error Interest_Rate_Overflow();
}
