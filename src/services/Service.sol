// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IService } from "../interfaces/IService.sol";
import { IManager } from "../interfaces/IManager.sol";
import { Vault } from "../Vault.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    IManager public immutable manager;
    address public guardian;
    mapping(address => uint256) public exposures;
    Agreement[] public agreements;
    ServiceStatus public status;
    uint256 public id;

    constructor(string memory _name, string memory _symbol, address _manager) ERC721(_name, _symbol) {
        manager = IManager(_manager);
        status = ServiceStatus.ACTIVE;
        id = 0;
    }

    modifier onlyGuardian() {
        if (guardian != msg.sender && owner() != msg.sender) revert RestrictedAccess();
        _;
    }

    modifier unlocked() {
        if (status != ServiceStatus.ACTIVE) revert Locked();
        _;
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

    function suspend() external onlyGuardian {
        status = ServiceStatus.SUSPENDED;

        emit ServiceStatusWasChanged(status);
    }

    function liftSuspension() external onlyOwner {
        assert(status != ServiceStatus.LOCKED);

        status = ServiceStatus.ACTIVE;

        emit ServiceStatusWasChanged(status);
    }

    function lock() external onlyOwner {
        status = ServiceStatus.LOCKED;

        emit ServiceStatusWasChanged(status);
    }

    ///// Service functions /////
    function _saveAgreement(Agreement memory agreement) internal {
        Agreement storage newAgreement = agreements.push();
        newAgreement.status = Status.OPEN;
        newAgreement.createdAt = block.timestamp;

        for (uint256 loansIndex = 0; loansIndex < agreement.loans.length; loansIndex++) {
            newAgreement.loans.push(agreement.loans[loansIndex]);
        }

        for (uint256 collateralIndex = 0; collateralIndex < agreement.collaterals.length; collateralIndex++) {
            newAgreement.collaterals.push(agreement.collaterals[collateralIndex]);
        }
    }

    /// @notice creates a new service agreement
    /// @param order a struct containing data on the agreement and extra params
    function open(Order calldata order) public virtual unlocked {
        // Save agreement in memory to allow editing
        Agreement memory agreement = order.agreement;

        // Hook
        _beforeOpening(agreement, order.data);

        // Body
        _open(agreement, order.data);
        _safeMint(msg.sender, id++);

        // Hook
        _afterOpening(agreement, order.data);

        _saveAgreement(agreement);
    }

    function _open(Agreement memory agreement, bytes calldata data) internal virtual {}

    function _beforeOpening(Agreement memory agreement, bytes calldata data) internal virtual {}

    function _afterOpening(Agreement memory agreement, bytes calldata data) internal virtual {}

    /// @notice closes an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param data extra custom data required by the specific service
    function close(uint256 tokenID, bytes calldata data) public virtual editable(tokenID) {
        Agreement memory agreement = agreements[tokenID];

        // Hook
        _beforeClosing(tokenID, agreement, data);

        // Body
        agreements[tokenID].status = Status.CLOSED;
        _burn(tokenID);
        _close(tokenID, agreement, data);

        // Hook
        _afterClosing(tokenID, agreement, data);
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal virtual {}

    function _beforeClosing(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal virtual {}

    function _afterClosing(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal virtual {}

    /// @notice modifies an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param agreement a struct containing new data on loan, collateral and item type
    /// @param data extra custom data required by the specific service
    function edit(uint256 tokenID, Agreement calldata agreement, bytes calldata data)
        public
        virtual
        unlocked
        editable(tokenID)
    {}

    function getAgreement(uint256 tokenID)
        public
        view
        returns (IService.Loan[] memory, IService.Collateral[] memory, uint256, IService.Status)
    {
        Agreement memory agreement = agreements[tokenID - 1];
        return (agreement.loans, agreement.collaterals, agreement.createdAt, agreement.status);
    }
}
