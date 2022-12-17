// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @dev constant value IR model, used for testing
contract ConstantRateModel {
    uint256 public immutable value;

    constructor(uint256 _value) {
        assert(_value > 0);

        value = _value;
    }

    function computeInterestRate(uint256 amount, uint256 freeLiquidity) internal returns (uint256) {
        return value;
    }
}
