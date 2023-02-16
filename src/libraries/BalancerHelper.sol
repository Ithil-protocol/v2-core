// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IBalancerVault } from "../interfaces/external/balancer/IBalancerVault.sol";
import { WeightedMath } from "./external/Balancer/WeightedMath.sol";
import { FloatingPointMath } from "./FloatingPointMath.sol";

/// @title    BalancerHelper library
/// @author   Ithil
/// @notice   A library to perform the most common operations on Balancer
library BalancerHelper {
    function swap(
        address vault,
        bytes32 poolId,
        address from,
        address to,
        uint256 amountIn,
        uint256 minOut,
        uint256 deadline
    ) public returns (uint256) {
        IBalancerVault.SingleSwap memory swapData = IBalancerVault.SingleSwap(
            poolId,
            IBalancerVault.SwapKind.GIVEN_IN,
            from,
            to,
            amountIn,
            ""
        );
        IBalancerVault.FundManagement memory tokenData = IBalancerVault.FundManagement(
            msg.sender,
            false,
            payable(msg.sender),
            false
        );

        return IBalancerVault(vault).swap(swapData, tokenData, minOut, deadline);
    }

    function exitExactBPTInForTokensOut(uint256[] memory balances, uint256 bptAmountIn, uint256 totalSupply)
        public
        pure
        returns (uint256[] memory)
    {
        uint256[] memory amountsOut = WeightedMath._calcTokensOutGivenExactBptIn(balances, bptAmountIn, totalSupply);
        return amountsOut;
    }

    function exitBPTInForExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 totalSupply,
        uint256 swapFee
    ) public pure returns (uint256) {
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
}
