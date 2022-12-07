// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @title    GeneralMath library
/// @author   Ithil
/// @notice   A library to perform the most common math operations
library GeneralMath {
    // Recall that type(uint256).max = 2^256-1, type(int256).max = 2^255 - 1, type(int256).min = -2^255

    // Never throws, returns min(a+b,2^256-1)
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > type(uint256).max - b) {
            return type(uint256).max;
        } else {
            return a + b;
        }
    }

    // Never throws, returns max(a-b,0)
    function positiveSub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a - b;
        } else {
            return 0;
        }
    }

    // Throws if c = 0
    function safeMulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (b == 0) return 0;
        if (a < type(uint256).max / b) return (a * b) / c;
        else {
            if (c >= b) return a - (a / c) * (c - b);
            else if (a / c < type(uint256).max / (b - c)) return safeAdd(a, (a / c) * (b - c));
            else return type(uint256).max;
        }
    }

    // Throws if b = 0 and a != 0
    function ceilingDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a > 0) c = 1 + (a - 1) / b;
    }

    // Throws if c = 0 and both a != 0, b != 0
    function mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return ceilingDiv(a * b, c);
    }

    // Throws if c = 0
    function mulDivDown(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return (a * b) / c;
    }

    // Never throws, returns max(a,b)
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? b : a;
    }

    // Never throws, returns min(a,b)
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
