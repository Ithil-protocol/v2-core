// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

/// @title    GeneralMath library
/// @author   Ithil
/// @notice   A library to perform the most common math operations
library GeneralMath {
    uint256 public constant RESOLUTION = 1e18;

    /// @dev Never throws, returns min(a+b,2^256-1)
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > type(uint256).max - b) {
            return type(uint256).max;
        } else {
            return a + b;
        }
    }

    /// @dev Never throws, returns max(a-b,0)
    function positiveSub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a - b;
        } else {
            return 0;
        }
    }

    /// @dev Throws only if c = 0
    function safeMulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (b == 0 || a == 0) return 0;
        if (c == b) return a;
        if (c == a) return b;
        if (a <= type(uint256).max / b || b <= type(uint256).max / a) return (a * b) / c;
        if (c > b || c > a) return a > b ? a / (c / b) : b / (c / a);
        if (a / c < type(uint256).max / (b - c)) return safeAdd(a, (a / c) * (b - c));
        return type(uint256).max;
    }

    /**
     * @dev Computes uint256 a * 2^128 + b
     * warning: if b >= 2^128, this cannot be unpacked anymore
     * throws if a >= 2^128
     * note: the natural datatype here is uint128 which never throws, but this involves many casts
     */
    function packInUint(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a << 128) + b;
    }

    /// @dev division with remainder of a by 2^128, never throws
    function unpackUint(uint256 a) internal pure returns (uint256, uint256) {
        return (a >> 128, a % (1 << 128));
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
