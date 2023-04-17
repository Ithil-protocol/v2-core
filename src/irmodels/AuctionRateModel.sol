// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";
import { IService } from "../interfaces/IService.sol";
import { DebitService } from "../services/DebitService.sol";
import { BaseRiskModel } from "../services/BaseRiskModel.sol";

/// @dev IR = baseIR + spread
/// Rate model in which baseIR is based on a Dutch auction
/// GeneralMath.RESOLUTION corresponds to 1, i.e. an interest rate of 100%
abstract contract AuctionRateModel is Ownable, BaseRiskModel {
    using GeneralMath for uint256;

    error InvalidInitParams();
    error InterestRateOverflow();
    error AboveRiskThreshold();

    /**
     * @dev gas saving trick
     * latest is a timestamp and base < GeneralMath.RESOLUTION, they all fit in uint256
     * latestAndBase = timestamp * 2^128 + base
     */
    mapping(address => uint256) public halvingTime;
    mapping(address => uint256) public riskSpreads;
    mapping(address => uint256) public latestAndBase;

    function setRiskParams(address token, uint256 riskSpread, uint256 baseRate, uint256 halfTime) external onlyOwner {
        if (baseRate > GeneralMath.RESOLUTION || riskSpread > GeneralMath.RESOLUTION || halfTime == 0)
            revert InvalidInitParams();
        riskSpreads[token] = riskSpread;
        latestAndBase[token] = GeneralMath.packInUint(block.timestamp, baseRate);
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

    function computeBaseRateAndSpread(IService.Loan memory loan, uint256 freeLiquidity)
        public
        view
        returns (uint256, uint256)
    {
        (uint256 latestBorrow, uint256 base) = GeneralMath.unpackUint(latestAndBase[loan.token]);
        // Increase base due to new borrow and then
        // apply time based discount: after halvingTime it is divided by 2
        uint256 newBase = base.safeMulDiv(freeLiquidity, freeLiquidity - loan.amount).safeMulDiv(
            halvingTime[loan.token],
            block.timestamp - latestBorrow + halvingTime[loan.token]
        );
        uint256 spread = riskSpreadFromMargin(loan.token, loan.amount, loan.margin);
        return (newBase, spread);
    }

    function _updateBase(IService.Loan memory loan, uint256 freeLiquidity) internal returns (uint256, uint256) {
        (uint256 newBase, uint256 spread) = computeBaseRateAndSpread(loan, freeLiquidity);
        // Reset new base and latest borrow, force IR stays below resolution
        if (newBase >= GeneralMath.RESOLUTION) revert InterestRateOverflow();
        latestAndBase[loan.token] = GeneralMath.packInUint(block.timestamp, newBase);

        return (newBase, spread);
    }

    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal override(BaseRiskModel) {
        (uint256 baseRate, uint256 spread) = _updateBase(loan, freeLiquidity);
        (uint256 requestedIr, uint256 requestedSpread) = loan.interestAndSpread.unpackUint();
        if (requestedIr < baseRate || requestedSpread < spread) revert AboveRiskThreshold();
    }
}
