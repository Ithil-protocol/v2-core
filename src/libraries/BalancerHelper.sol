// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.12;

import { FloatingPointMath } from "./FloatingPointMath.sol";

/// @title    BalancerHelper library
/// @author   Ithil
/// @notice   A library to perform the most common operations on Balancer
library BalancerHelper {
    error BalancerStrategy__Token_Not_In_Pool(address token);

    function computeBptOut(
        uint256 amountIn,
        uint256 totalBptSupply,
        uint256 totalTokenBalance,
        uint256 normalisedWeight,
        uint256 swapPercentageFee
    ) internal pure returns (uint256) {
        uint256 swapFee = FloatingPointMath.mul(
            FloatingPointMath.mul(amountIn, FloatingPointMath.REFERENCE - normalisedWeight),
            swapPercentageFee
        );
        uint256 balanceRatio = FloatingPointMath.div(totalTokenBalance + amountIn - swapFee, totalTokenBalance);
        uint256 invariantRatio = FloatingPointMath.power(balanceRatio, normalisedWeight);
        return
            invariantRatio > FloatingPointMath.REFERENCE
                ? FloatingPointMath.mul(totalBptSupply, invariantRatio - FloatingPointMath.REFERENCE)
                : 0;
    }

    function computeAmountOut(
        uint256 amountIn,
        uint256 totalBptSupply,
        uint256 totalTokenBalance,
        uint256 normalisedWeight,
        uint256 swapPercentageFee
    ) internal pure returns (uint256) {
        uint256 invariantRatio = FloatingPointMath.div(totalBptSupply - amountIn, totalBptSupply);
        uint256 balanceRatio = FloatingPointMath.power(
            invariantRatio,
            FloatingPointMath.div(FloatingPointMath.REFERENCE, normalisedWeight)
        );
        uint256 amountOutWithoutFee = FloatingPointMath.mul(
            totalTokenBalance,
            FloatingPointMath.complement(balanceRatio)
        );
        uint256 taxableAmount = FloatingPointMath.mul(
            amountOutWithoutFee,
            FloatingPointMath.complement(normalisedWeight)
        );
        uint256 nonTaxableAmount = FloatingPointMath.sub(amountOutWithoutFee, taxableAmount);
        uint256 taxableAmountMinusFees = FloatingPointMath.mul(
            taxableAmount,
            FloatingPointMath.complement(swapPercentageFee)
        );

        return nonTaxableAmount + taxableAmountMinusFees;
    }
}
