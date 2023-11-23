// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { RESOLUTION } from "../Constants.sol";

library FloatingPointMath {
    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / RESOLUTION;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * RESOLUTION) / y;
    }

    function complement(uint256 x) internal pure returns (uint256) {
        return x < RESOLUTION ? RESOLUTION - x : 0;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        // Fixed Point addition is the same as regular checked addition

        assert(b <= a);
        uint256 c = a - b;
        return c;
    }

    // Assumes base is "near 10^18", as it will be the case for the typical Balancer pools
    // Balancer's math module also uses Taylor expansion, thus they also assume small numbers
    // exp is also a floating number, as the normalised weights of Balancer pools
    // 2-th order Taylor expansion
    function power(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 mantissa = base > RESOLUTION ? base - RESOLUTION : RESOLUTION - base;

        // First order is already quite near
        uint256 firstOrder = base > RESOLUTION ? RESOLUTION + mul(mantissa, exp) : RESOLUTION - mul(mantissa, exp);
        uint256 den = 2 * (RESOLUTION ** 3);

        if (exp > RESOLUTION) {
            uint256 num = exp * (exp - RESOLUTION) * (mantissa ** 2);
            return firstOrder + num / den;
        } else {
            uint256 num = exp * (RESOLUTION - exp) * (mantissa ** 2);
            return firstOrder - num / den;
        }
    }
}
