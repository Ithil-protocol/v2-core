// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

/// @title    Interface of the Manager contract
/// @author   Ithil
/// @notice   Manages lending and borrowing from and to the ERC4626 vaults
interface IManager {
    struct CapsAndExposures {
        uint256 percentageCap;
        uint256 absoluteCap;
        uint256 exposure;
    }

    function salt() external pure returns (bytes32);

    function vaults(address token) external view returns (address);

    function caps(address service, address token) external view returns (uint256, uint256, uint256);

    function create(address token) external returns (address);

    function setCap(address service, address token, uint256 percentageCap, uint256 absoluteCap) external;

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external;

    function borrow(address token, uint256 amount, uint256 loan, address receiver) external returns (uint256, uint256);

    function repay(address token, uint256 amount, uint256 debt, address repayer) external;

    event SpreadWasUpdated(address indexed service, address indexed token, uint256 spread);
    event CapWasUpdated(address indexed service, address indexed token, uint256 percentageCap, uint256 absoluteCap);
    event TokenWasRemovedFromService(address indexed service, address indexed token);

    error VaultMissing();
    error RestrictedToWhitelisted();
    error RestrictedToOwner();
    error InvestmentCapExceeded(uint256 investedPortion);
    error AbsoluteCapExceeded(uint256 exposure);
    error MaxAmountExceeded();
}
