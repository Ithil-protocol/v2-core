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

    // Never throws, returns min(a+b,2^256-1)
    function safeAdd(int256 a, uint256 b) internal pure returns (int256) {
        if (b > uint256(type(int256).max)) {
            // Following casting does not overflow because argument is less than 2^255 - 1
            int256 diff = int256(b - uint256(type(int256).max) - 1);
            // Since diff > 0, -diff does not overflow
            if (a < -diff) {
                // In this case a + b <= type(int256).max therefore we can deliver the exact sum
                // Since a < 0, -a might overflow, thus we add 1
                a++;
                // Now 0 <= a <= type(int256).max, therefore b + a >= 1 and subtraction does not underflow
                return int256(b - uint256(-a) - 1);
            }
            // b - diff = 2^255 therefore summing with a would overflow
            else return type(int256).max;
        }
        // If b is less than type(int256).max it can be downcasted and we adopt usual math
        else return a > type(int256).max - int256(b) ? type(int256).max : a + int256(b);
    }

    // Never throws, returns max(a+b,-2^255)
    function safeSub(int256 a, uint256 b) internal pure returns (int256) {
        if (b > uint256(type(int256).max)) {
            int256 diff = int256(b - uint256(type(int256).max) - 1);
            if (a > diff) {
                // In this case b - a <= type(int256).max therefore we can deliver the exact difference
                // We have 0 <= a < b because b > type(int256).max
                return -int256(b - uint256(a));
            }
            // diff - b = type(int256).min therefore subtracting a would underflow
            else return type(int256).min;
        }
        // If b is less than type(int256).max it can be downcasted and we adopt usual math
        else {
            return a < type(int256).min + int256(b) ? type(int256).min : a - int256(b);
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

    // Never throws, returns min(max(a-b,0),2^256-1)
    function positiveSub(uint256 a, int256 b) internal pure returns (uint256) {
        if (b > 0) return positiveSub(a, uint256(b));
        else return safeAdd(a, uint256(-b));
    }

    // Throws if c = 0 and if c - b underflows
    // Best precision if a > c > b as is the case in calculateLockedProfits
    function safeMulDiv(int256 a, int256 b, int256 c) internal pure returns (int256) {
        if (b == 0) return 0;
        bool overflow = a >= 0 ? a >= type(int256).max / b : a <= type(int256).min / b;
        return overflow ? a - (a / c) * (c - b) : (a * b) / c;
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
