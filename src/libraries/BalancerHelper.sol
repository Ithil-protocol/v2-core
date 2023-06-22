// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBalancerVault } from "../interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "../interfaces/external/balancer/IBalancerPool.sol";
import { IProtocolFeesCollector } from "../interfaces/external/balancer/IProtocolFeesCollector.sol";
import { FloatingPointMath } from "./FloatingPointMath.sol";
import { WeightedMath } from "./external/Balancer/WeightedMath.sol";

/// @title    BalancerHelper library
/// @author   Ithil
/// @notice   A library to perform the most common operations on Balancer
library BalancerHelper {
    function exitExactBPTInForTokensOut(
        uint256[] memory balances,
        uint256 bptAmountIn,
        uint256 totalSupply
    ) internal pure returns (uint256[] memory) {
        uint256[] memory amountsOut = WeightedMath._calcTokensOutGivenExactBptIn(balances, bptAmountIn, totalSupply);
        return amountsOut;
    }

    function exitBPTInForExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 totalSupply,
        uint256 swapFee
    ) internal pure returns (uint256) {
        // _upscaleArray(amountsOut);

        uint256 bptAmountIn = WeightedMath._calcBptInGivenExactTokensOut(
            balances,
            normalizedWeights,
            amountsOut,
            totalSupply,
            swapFee
        );

        return bptAmountIn;
    }

    function getTokenIndex(address[] memory tokens, address token) internal pure returns (uint8) {
        for (uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) return i;
        }

        return type(uint8).max;
    }

    function _modifyBalancesWithFees(
        address poolAddress,
        address protocolFeeCollector,
        uint256[] memory scalingFactors,
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256 maximumWeightIndex
    ) internal view {
        uint256 length = scalingFactors.length;
        for (uint256 i = 0; i < length; i++) balances[i] *= scalingFactors[i];

        uint256[] memory dueProtocolFeeAmounts = new uint256[](length);
        dueProtocolFeeAmounts[maximumWeightIndex] = WeightedMath._calcDueTokenProtocolSwapFeeAmount(
            balances[maximumWeightIndex],
            normalizedWeights[maximumWeightIndex],
            IBalancerPool(poolAddress).getLastInvariant(),
            WeightedMath._calculateInvariant(normalizedWeights, balances),
            IProtocolFeesCollector(protocolFeeCollector).getSwapFeePercentage()
        );

        balances[maximumWeightIndex] -= dueProtocolFeeAmounts[maximumWeightIndex];
    }

    // Assumes balances are already upscaled and downscales them back together with balances
    function calculateExpectedBPTToExit(
        address poolAddress,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256[] memory scalingFactors,
        address protocolFeeCollector,
        uint256 maximumWeightIndex
    ) internal view returns (uint256) {
        uint256 length = scalingFactors.length;
        uint256[] memory normalizedWeights = IBalancerPool(poolAddress).getNormalizedWeights();
        _modifyBalancesWithFees(
            poolAddress,
            protocolFeeCollector,
            scalingFactors,
            balances,
            normalizedWeights,
            maximumWeightIndex
        );

        for (uint256 i = 0; i < length; i++) amountsOut[i] *= scalingFactors[i];

        uint256 expectedBpt = WeightedMath._calcBptInGivenExactTokensOut(
            balances,
            normalizedWeights,
            amountsOut,
            IERC20(poolAddress).totalSupply(),
            IBalancerPool(poolAddress).getSwapFeePercentage()
        );

        for (uint256 i = 0; i < length; i++) {
            amountsOut[i] /= scalingFactors[i];
            balances[i] /= scalingFactors[i];
        }

        return expectedBpt;
    }

    // Assumes balances are already upscaled and downscales them back together with balances
    function calculateExpectedTokensFromBPT(
        address poolAddress,
        address protocolFeeCollector,
        uint256[] memory balances,
        uint256[] memory scalingFactors,
        uint256[] memory normalizedWeights,
        uint256 maximumWeightIndex,
        uint256 amount,
        uint256 totalSupply
    ) internal view returns (uint256[] memory) {
        uint256[] memory normalizedWeights = IBalancerPool(poolAddress).getNormalizedWeights();

        _modifyBalancesWithFees(
            poolAddress,
            protocolFeeCollector,
            scalingFactors,
            balances,
            normalizedWeights,
            maximumWeightIndex
        );
        uint256[] memory expectedTokens = WeightedMath._calcTokensOutGivenExactBptIn(balances, amount, totalSupply);

        for (uint256 i = 0; i < scalingFactors.length; i++) {
            expectedTokens[i] /= scalingFactors[i];
            balances[i] /= scalingFactors[i];
        }

        return expectedTokens;
    }
}
