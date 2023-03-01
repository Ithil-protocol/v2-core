// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

interface IZeroExRouter {
    struct Transformation {
        // The deployment nonce for the transformer.
        // The address of the transformer contract will be derived from this
        // value.
        uint32 deploymentNonce;
        // Arbitrary data to pass to the transformer.
        bytes data;
    }

    /**
     * @dev swap function
     * @param inputToken The token being provided by the taker. If `0xeee...`, ETH is implied
     * @param outputToken The token to be acquired by the taker. `0xeee...` implies ETH.
     * @param inputTokenAmount The amount of `inputToken` to take from the taker.
     *  If set to `uint256(-1)`, the entire spendable balance of the taker will be sold.
     * @param minOutputTokenAmount The minimum amount of `outputToken` the taker must receive for the tx to succeed.
     *  If set to zero, the minimum output token transfer will not be asserted.
     * @param transformations The transformations to execute on the token balance(s) in sequence.
     */
    function transformERC20(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        Transformation[] calldata transformations
    ) external payable;
}
