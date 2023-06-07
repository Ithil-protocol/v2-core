// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title    Interface of the Vault contract
/// @author   Ithil
interface IVault is IERC4626 {
    function creationTime() external view returns (uint256);

    function feeUnlockTime() external view returns (uint256);

    function netLoans() external view returns (uint256);

    function latestRepay() external view returns (uint256);

    function currentProfits() external view returns (uint256);

    function currentLosses() external view returns (uint256);

    function freeLiquidity() external view returns (uint256);

    function setFeeUnlockTime(uint256 _feeUnlockTime) external;

    function sweep(address to, address token) external;

    function borrow(uint256 assets, uint256 loan, address receiver) external returns (uint256, uint256);

    function repay(uint256 assets, uint256 debt, address repayer) external;

    function getFeeStatus() external view returns (uint256, uint256, uint256);

    // Events
    event DegradationCoefficientWasUpdated(uint256 degradationCoefficient);
    event Deposited(address indexed user, address indexed receiver, uint256 assets, uint256 shares);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Borrowed(address indexed receiver, uint256 assets);
    event Repaid(address indexed repayer, uint256 amount, uint256 debt);
    event DirectMint(address indexed receiver, uint256 shares, uint256 increasedAssets);
    event DirectBurn(address indexed receiver, uint256 shares, uint256 distributedAssets);

    error InsufficientLiquidity();
    error InsufficientFreeLiquidity();
    error BurnThresholdExceeded();
    error FeeUnlockTimeOutOfRange();
    error RestrictedToOwner();
    error LoanHigherThanAssetsInBorrow();
}
