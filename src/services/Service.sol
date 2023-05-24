// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IService } from "../interfaces/IService.sol";
import { IManager } from "../interfaces/IManager.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";
import { Vault } from "../Vault.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    IManager public immutable manager;
    address public guardian;
    mapping(address => uint256) public exposures;
    Agreement[] public agreements;
    bool public locked;
    uint256 public id;
    uint256 public immutable deadline;

    constructor(string memory _name, string memory _symbol, address _manager, uint256 _deadline)
        ERC721(_name, _symbol)
    {
        manager = IManager(_manager);
        locked = false;
        id = 0;
        deadline = _deadline;
    }

    modifier onlyGuardian() {
        if (guardian != msg.sender && owner() != msg.sender) revert RestrictedAccess();
        _;
    }

    modifier unlocked() {
        if (locked) revert Locked();
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

    function toggleLock(bool _locked) external onlyGuardian {
        locked = _locked;

        emit LockWasToggled(locked);
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

        // Body
        _open(agreement, order.data);
        _safeMint(msg.sender, id++);

        _saveAgreement(agreement);
    }

    /// @notice closes an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param data extra custom data required by the specific service
    function close(uint256 tokenID, bytes calldata data) public virtual editable(tokenID) returns (uint256[] memory) {
        Agreement memory agreement = agreements[tokenID];

        // Body
        // The following, with the editable modifier, avoids reentrancy
        agreements[tokenID].status = Status.CLOSED;
        _close(tokenID, agreement, data);
        // Burning after closing since owner may be needed during closure
        _burn(tokenID);
        // for (uint256 index = 0; index < agreement.loans.length; index++)
        //     amountsOut[index] = IERC20(agreement.loans[index].token).balanceOf(address(this)) - amountsOut[index];

        // return amountsOut;
    }

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
        Agreement memory agreement = agreements[tokenID];
        return (agreement.loans, agreement.collaterals, agreement.createdAt, agreement.status);
    }

    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual;
}
