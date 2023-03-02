// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

interface ISwapper {
    function swap(address from, address to, uint256 amount, uint256 minOut, bytes calldata data) external;

    event SwapWasExecuted(address indexed from, address indexed to, uint256 sold, uint256 obtained);
    error TooMuchSlippage();
}
