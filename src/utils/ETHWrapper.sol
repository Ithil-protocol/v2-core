// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

interface IWETH {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

abstract contract ETHWrapper {
    IWETH public immutable weth;

    error ETH_Unstake_Failed(bytes err);
    error ETH_Callback_Failed();

    constructor(address _weth) {
        weth = IWETH(_weth);
    }

    function wrap() external payable {
        weth.deposit{ value: msg.value }();
    }

    function unwrap(uint256 amount, address recipient) external {
        weth.withdraw(amount);

        // slither-disable-next-line arbitrary-send-eth
        (bool success, bytes memory data) = payable(recipient).call{ value: amount }("");
        if (!success) revert ETH_Unstake_Failed(data);
    }

    // only accept ETH from the WETH contract
    receive() external payable {
        if (msg.sender != address(weth)) revert ETH_Callback_Failed();
    }
}
