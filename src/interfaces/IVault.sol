// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

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

    function getFeeStatus() external view returns (uint256, uint256, uint256, uint256);

    function getLoansAndLiquidity() external view returns (uint256, uint256);

    function toggleLock() external;

    function isLocked() external view returns (bool);

    // Events
    event DegradationCoefficientWasUpdated(uint256 degradationCoefficient);
    event Borrowed(address indexed receiver, uint256 assets);
    event Repaid(address indexed repayer, uint256 amount, uint256 debt);
    event LockToggled(bool isLocked);

    error InsufficientLiquidity();
    error InsufficientFreeLiquidity();
    error FeeUnlockTimeOutOfRange();
    error RestrictedToOwner();
    error LoanHigherThanAssetsInBorrow();
    error Locked();
}
