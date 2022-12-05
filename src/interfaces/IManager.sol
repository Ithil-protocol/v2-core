// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @title    Interface of the Manager contract
/// @author   Ithil
/// @notice   Manages lending and borrowing from and to the ERC4626 vaults
interface IManager {
    event ServiceWasAdded(address indexed service);

    event ServiceWasRemoved(address indexed service);

    error Vault_Missing();

    error Restricted_To_Whitelisted_Services();

    /// @notice thrown when amount of assets received is above the max set by caller
    error Max_Amount_Exceeded();

    function salt() external pure returns (bytes32);

    function vaults(address token) external view returns (address);

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external;

    function borrow(address token, uint256 amount) external;

    function repay(address token, uint256 amount, uint256 debt) external;

    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn) external returns (uint256);

    function directBurn(address token, address from, uint256 shares, uint256 maxAmountIn) external returns (uint256);
}
