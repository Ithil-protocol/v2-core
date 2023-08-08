// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IService } from "../interfaces/IService.sol";
import { IManager } from "../interfaces/IManager.sol";
import { Vault } from "../Vault.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
    IManager public immutable manager;
    address public guardian;
    Agreement[] public agreements;
    bool public locked;
    uint256 public id;
    uint256 public immutable deadline;

    event PositionOpened(uint256 indexed id, address indexed user, Agreement agreement);
    event PositionClosed(uint256 indexed id, address indexed user, Agreement agreement);

    constructor(
        string memory _name,
        string memory _symbol,
        address _manager,
        uint256 _deadline
    ) ERC721(_name, _symbol) {
        manager = IManager(_manager);
        locked = false;
        id = 0;
        deadline = _deadline;
    }

    modifier onlyGuardian() {
        if (guardian != msg.sender && owner() != msg.sender) revert RestrictedAccess();
        _;
    }

    // besides locking the entire service, this also serves as reentrancy guard
    // to prevent a reentrancy switching the msg.sender to a non-ERC721 receivable
    // which would produce positions impossible to close
    // in order to be effective, it must be enforced __downstream__
    // because saving agreements always come at the end
    modifier unlocked() {
        if (locked) revert Locked();
        locked = true;
        _;
        locked = false;
    }

    modifier editable(uint256 tokenID) {
        if (agreements[tokenID].status != Status.OPEN) revert InvalidStatus();
        _;
    }

    ///// Admin functions /////

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;

        emit GuardianWasUpdated(guardian);
    }

    function toggleLock(bool _locked) external onlyGuardian {
        locked = _locked;

        emit LockWasToggled(locked);
    }

    ///// Service functions /////
    function _saveAgreement(Agreement memory agreement) internal {
        Agreement storage newAgreement = agreements.push();
        newAgreement.status = Status.OPEN;
        // we might want to change the createdAt to deal with locks without the need of an extra datum
        newAgreement.createdAt = agreement.createdAt == 0 ? block.timestamp : agreement.createdAt;

        for (uint256 loansIndex = 0; loansIndex < agreement.loans.length; loansIndex++) {
            newAgreement.loans.push(agreement.loans[loansIndex]);
        }

        for (uint256 collateralIndex = 0; collateralIndex < agreement.collaterals.length; collateralIndex++) {
            newAgreement.collaterals.push(agreement.collaterals[collateralIndex]);
        }
    }

    /// @notice creates a new service agreement
    /// @param order a struct containing data on the agreement and extra params
    function open(Order calldata order) public virtual override {
        // Save agreement in memory to allow editing
        Agreement memory agreement = order.agreement;

        // Body
        _open(agreement, order.data);

        _saveAgreement(agreement);

        _safeMint(msg.sender, id++);

        emit PositionOpened(id, msg.sender, agreement);
    }

    /// @notice closes an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param data extra custom data required by the specific service
    function close(
        uint256 tokenID,
        bytes calldata data
    ) public virtual override editable(tokenID) returns (uint256[] memory) {
        Agreement memory agreement = agreements[tokenID];

        // Body
        // The following, with the editable modifier, avoids reentrancy
        agreements[tokenID].status = Status.CLOSED;
        _close(tokenID, agreement, data);

        emit PositionClosed(tokenID, ownerOf(tokenID), agreement);

        // Burning after closing since owner may be needed during closure
        _burn(tokenID);
    }

    /// @notice modifies an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param agreement a struct containing new data on loan, collateral and item type
    /// @param data extra custom data required by the specific service
    function edit(
        uint256 tokenID,
        Agreement calldata agreement,
        bytes calldata data
    ) public virtual override unlocked editable(tokenID) {}

    function getAgreement(
        uint256 tokenID
    ) public view override returns (IService.Loan[] memory, IService.Collateral[] memory, uint256, IService.Status) {
        Agreement memory agreement = agreements[tokenID];
        return (agreement.loans, agreement.collaterals, agreement.createdAt, agreement.status);
    }

    function getUserAgreements() public view override returns (Agreement[] memory, uint256[] memory) {
        uint256 balance = balanceOf(msg.sender);
        Agreement[] memory userAgreements = new Agreement[](balance);
        uint256[] memory ids = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            ids[i] = tokenOfOwnerByIndex(msg.sender, i);
            userAgreements[i] = agreements[ids[i]];
        }

        return (userAgreements, ids);
    }

    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual;
}
