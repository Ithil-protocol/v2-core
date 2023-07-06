// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IService is IERC721Enumerable {
    // Owed is forcefully ERC20: the Manager only deals with ERC20/ERC4626
    struct Loan {
        address token;
        uint256 amount;
        uint256 margin;
        uint256 interestAndSpread;
    }

    enum ItemType {
        ERC20,
        ERC721,
        ERC1155
    }

    enum Status {
        UNDEFINED,
        OPEN,
        CLOSED
    }

    struct Collateral {
        ItemType itemType;
        address token;
        uint256 identifier;
        uint256 amount;
    }

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
}
