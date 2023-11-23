// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IService } from "../interfaces/IService.sol";
import { DebitService } from "../services/DebitService.sol";
import { BaseRiskModel } from "../services/BaseRiskModel.sol";

/// @dev IR = baseIR + spread
/// Rate model in which baseIR is based on a Dutch auction
/// 1e18 corresponds to 1, i.e. an interest rate of 100%
abstract contract AuctionRateModel is Ownable, BaseRiskModel {
    error InvalidInitParams();
    error InterestRateOverflow();
    error AboveRiskThreshold();
    error ZeroMarginLoan();

    /**
     * @dev gas saving trick
     * latest is a timestamp and base < 1e18, they all fit in uint256
     * latestAndBase = timestamp * 2^128 + base
     */
    mapping(address => uint256) public halvingTime;
    mapping(address => uint256) public riskSpreads;
    mapping(address => uint256) public latestAndBase;

    function setRiskParams(address token, uint256 riskSpread, uint256 baseRate, uint256 halfTime) external onlyOwner {
        if (baseRate > 1e18 || riskSpread > 1e18 || halfTime == 0) revert InvalidInitParams();
        riskSpreads[token] = riskSpread;
        latestAndBase[token] = (block.timestamp << 128) + baseRate;
        halvingTime[token] = halfTime;
    }

    /// @dev Defaults to riskSpread = baseRiskSpread * amount / margin
    function _riskSpreadFromMargin(address token, uint256 amount, uint256 margin) internal view returns (uint256) {
        if (amount == 0) return 0;
        // We do not allow a zero margin on a loan with positive amount
        if (margin == 0) revert ZeroMarginLoan();
        return (riskSpreads[token] * amount) / margin;
    }

    /**
     * @dev calculating the end IR value
     * throws if block.timestamp is smaller than latestBorrow
     * throws if amount >= freeLiquidity
     * throws if spread > type(uint256).max - newBase
     */

    function computeBaseRateAndSpread(
        address token,
        uint256 loan,
        uint256 margin,
        uint256 freeLiquidity
    ) public view returns (uint256, uint256) {
        (uint256 latestBorrow, uint256 base) = (latestAndBase[token] >> 128, latestAndBase[token] % (1 << 128));
        // linear damping in which in 2*halfTime after the last borrow, the base is zero
        // just after latestBorrow, base is roughly unchanged
        uint256 dampedBase = block.timestamp < 2 * halvingTime[token] + latestBorrow
            ? (base * (2 * halvingTime[token] + latestBorrow - block.timestamp)) / (2 * halvingTime[token])
            : 0;
        // Increase base with a linear bump based on the risk spread
        uint256 newBase = dampedBase + ((riskSpreads[token] + dampedBase) * loan) / freeLiquidity;
        uint256 spread = _riskSpreadFromMargin(token, loan, margin);
        return (newBase, spread);
    }

    function _updateBase(IService.Loan memory loan, uint256 freeLiquidity) internal returns (uint256, uint256) {
        (uint256 newBase, uint256 spread) = computeBaseRateAndSpread(
            loan.token,
            loan.amount,
            loan.margin,
            freeLiquidity
        );
        // Reset new base and latest borrow, force IR stays below resolution
        if (newBase + spread >= 1e18) revert InterestRateOverflow();
        latestAndBase[loan.token] = (block.timestamp << 128) + newBase;

        return (newBase, spread);
    }

    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal override(BaseRiskModel) {
        (uint256 baseRate, uint256 spread) = _updateBase(loan, freeLiquidity);
        (uint256 requestedIr, uint256 requestedSpread) = (
            loan.interestAndSpread >> 128,
            loan.interestAndSpread % (1 << 128)
        );
        if (requestedIr < baseRate || requestedSpread < spread) revert AboveRiskThreshold();
    }
}
