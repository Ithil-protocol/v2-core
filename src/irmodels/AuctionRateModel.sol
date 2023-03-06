// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { GeneralMath } from "../libraries/GeneralMath.sol";
import { DebitService } from "../services/DebitService.sol";
import { IService } from "../interfaces/IService.sol";

/// @dev IR = baseIR + spread
/// Rate model in which baseIR is based on a Dutch auction
/// GeneralMath.RESOLUTION corresponds to 1, i.e. an interest rate of 100%
abstract contract AuctionRateModel is DebitService {
    using GeneralMath for uint256;

    error InvalidInitParams();
    error InterestRateOverflow();
    error AboveRiskThreshold();

    /**
     * @dev gas saving trick
     * latest is a timestamp and base < GeneralMath.RESOLUTION, they all fit in uint256
     * baseAndLatest = timestamp * 2^128 + base
     */
    mapping(address => uint256) public halvingTime;
    mapping(address => uint256) public riskSpreads;
    mapping(address => uint256) public baseAndLatest;

    function setRiskParams(address token, uint256 riskSpread, uint256 baseRate, uint256 halfTime) external onlyOwner {
        if (baseRate > GeneralMath.RESOLUTION || riskSpread > GeneralMath.RESOLUTION || halfTime == 0)
            revert InvalidInitParams();
        riskSpreads[token] = riskSpread;
        baseAndLatest[token] = GeneralMath.packInUint(block.timestamp, baseRate);
        halvingTime[token] = halfTime;
    }

    /// @dev Defaults to riskSpread = baseRiskSpread * amount / margin
    function riskSpreadFromMargin(address token, uint256 amount, uint256 margin) internal view returns (uint256) {
        return riskSpreads[token].safeMulDiv(amount, margin);
    }

    /**
     * @dev calculating the end IR value
     * throws if block.timestamp is smaller than latestBorrow
     * throws if amount >= freeLiquidity
     * throws if spread > type(uint256).max - newBase
     */
    function computeInterestRateAndUpdateBase(address token, uint256 amount, uint256 freeLiquidity)
        internal
        returns (uint256)
    {
        (uint256 latestBorrow, uint256 base) = GeneralMath.unpackUint(baseAndLatest[token]);
        // Increase base due to new borrow and then
        // apply time based discount: after halvingTime it is divided by 2
        uint256 newBase = base.safeMulDiv(freeLiquidity, freeLiquidity - amount).safeMulDiv(
            halvingTime[token],
            block.timestamp - latestBorrow + halvingTime[token]
        );
        // Reset new base and latest borrow, force IR stays below resolution
        if (newBase >= GeneralMath.RESOLUTION) revert InterestRateOverflow();
        baseAndLatest[token] = GeneralMath.packInUint(block.timestamp, newBase);

        return newBase;
    }

    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal override {
        uint256 baseRate = computeInterestRateAndUpdateBase(loan.token, loan.amount, freeLiquidity);
        uint256 spread = riskSpreadFromMargin(loan.token, loan.amount, loan.margin);
        (uint256 requestedIr, uint256 requestedSpread) = loan.interestAndSpread.unpackUint();
        if (requestedIr < baseRate || requestedSpread < spread) revert AboveRiskThreshold();
    }
}
