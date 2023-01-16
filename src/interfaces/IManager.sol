// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @title    Interface of the Manager contract
/// @author   Ithil
/// @notice   Manages lending and borrowing from and to the ERC4626 vaults
interface IManager {
    struct RiskParams {
        uint256 spread;
        uint256 cap;
        uint256 exposure;
    }

    function salt() external pure returns (bytes32);

    function vaults(address token) external view returns (address);

    function riskParams(address service, address token) external view returns (uint256, uint256, uint256);

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external;

    function borrow(address token, uint256 amount, address receiver) external returns (uint256, uint256);

    function repay(address token, uint256 amount, uint256 debt, address repayer) external;

    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn) external returns (uint256);

    function directBurn(address token, address from, uint256 shares, uint256 maxAmountIn) external returns (uint256);

    event SpreadWasUpdated(address indexed service, address indexed token, uint256 spread);

    event CapWasUpdated(address indexed service, address indexed token, uint256 cap);

    event TokenWasRemovedFromService(address indexed service, address indexed token);

    error Vault_Missing();

    error Restricted_To_Whitelisted_Services();

    error Invesment_Exceeded_Cap(uint256 investedPortion, uint256 investmentCap);

    /// @notice thrown when amount of assets received is above the max set by caller
    error Max_Amount_Exceeded();
}
