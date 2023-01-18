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
    Agreement[] public agreements;
    bool public locked;
    uint256 public id;

    constructor(string memory _name, string memory _symbol, address _manager) ERC721(_name, _symbol) {
        manager = IManager(_manager);
        locked = false;
        id = 0;
    }

    modifier onlyGuardian() {
        if(guardian != msg.sender && owner() != msg.sender) revert RestrictedAccess();
        _;
    }

    modifier unlocked() {
        if (locked) revert Locked();
        _;
    }

    modifier editable(uint256 tokenID) {
        if(agreements[tokenID].status == Status.OPEN) revert InvalidStatus();
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

    /// @notice creates a new service agreement
    /// @param order a struct containing data on the agreement and extra params
    function open(Order calldata order) public virtual unlocked {
        // Hook
        _beforeOpening(order.agreement, order.data);

        // Body
        assert(order.agreement.status == Status.OPEN); // @todo should we validate more params here?
        agreements.push(order.agreement);

        _open(order.agreement, order.data);
        _safeMint(msg.sender, id);

        // Hook
        _afterOpening(order.agreement, order.data);
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
        _beforeClosing(agreement, data);

        // Body
        agreements[tokenID].status = Status.CLOSED;
        _burn(tokenID);
        _close(agreement, data);

        // Hook
        _afterClosing(agreement, data);
    }

    function _close(Agreement memory agreement, bytes calldata data) internal virtual {}

    function _beforeClosing(Agreement memory agreement, bytes calldata data) internal virtual {}

    function _afterClosing(Agreement memory agreement, bytes calldata data) internal virtual {}

    /// @notice modifies an existing service agreement
    /// @param tokenID used to pull the agreement data and its owner
    /// @param agreement a struct containing new data on loan, collateral and item type
    /// @param data extra custom data required by the specific service
    function edit(uint256 tokenID, Agreement calldata agreement, bytes calldata data) public virtual unlocked editable(tokenID) {}
}
