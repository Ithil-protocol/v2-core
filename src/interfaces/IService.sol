// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IService is IERC721Enumerable {
    /// @dev Owed is forcefully ERC20: the Manager only deals with ERC20/ERC4626

    /**
     * @dev Represents a loan from the vault to the service
     * @param token The address of the ERC20 token
     * @param amount The amount of the loan
     * @param margin The margin posted for the loan
     * @param interestAndSpread The interest + spread combined into a single var
     */
    struct Loan {
        address token;
        uint256 amount;
        uint256 margin;
        uint256 interestAndSpread;
    }

    enum ItemType {
        UNDEFINED,
        ERC20,
        ERC721,
        ERC1155
    }

    enum Status {
        UNDEFINED,
        OPEN,
        CLOSED
    }

    /**
     * @dev Represents the collateral posted from the user to the service
     * @param itemType The type of token
     * @param token The address of the token contract
     * @param identifier The tokenID for NFTs (if ERC721 or ERC1155)
     * @param amount The amount of tokens posted
     */
    struct Collateral {
        ItemType itemType;
        address token;
        uint256 identifier;
        uint256 amount;
    }

    /**
     * @dev Stores the position opened by the user on a specific service
     * @param loans The loans from the vault to the service
     * @param collaterals The collaterals posted from the user to the service
     * @param createdAt The timestamp
     * @param status
     */
    struct Agreement {
        Loan[] loans;
        Collateral[] collaterals;
        uint256 createdAt;
        Status status;
    }

    struct Order {
        Agreement agreement;
        bytes data;
    }

    function open(Order calldata order) external;

    function close(uint256 tokenID, bytes calldata data) external returns (uint256[] memory);

    function edit(uint256 tokenID, Agreement calldata agreement, bytes calldata data) external;

    function getAgreement(
        uint256 tokenID
    ) external view returns (IService.Loan[] memory, IService.Collateral[] memory, uint256, IService.Status);

    function getUserAgreements() external view returns (Agreement[] memory, uint256[] memory);

    event BaseRiskSpreadWasUpdated(address indexed asset, uint256 indexed id, uint256 newValue);
    event LockWasToggled(bool status);
    event GuardianWasUpdated(address indexed newGuardian);

    error Locked();
    error RestrictedToOwner();
    error RestrictedAccess();
    error InvalidStatus();
    error InvalidParams();
}
