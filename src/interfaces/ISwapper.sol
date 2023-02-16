// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @title    Interface of the Swapper contract
/// @author   Ithil
/// @notice   Manages ERC20 swaps on different dexes
interface ISwapper {
    enum Dex {
        NONE,
        SUSHI,
        UNISWAPV2,
        BALANCER,
        CURVE,
        GMX
    }

    struct SwapData {
        Dex dex;
        address[] path;
        uint256 defaultSlippage;
        bytes data;
    }

    error SwapNotPossible();

    function swap(address from, address to, uint256 amountIn, uint256 minOut) external;
}
