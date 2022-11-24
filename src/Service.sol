// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Service is ERC721, Ownable {
    address public immutable manager;
    address public guardian;
    bool public locked;

    event LockWasToggled(bool status);
    event GuardianWasUpdated(address indexed newGuardian);
    error Locked();

    constructor(string memory _name, string memory _symbol, address _manager) ERC721(_name, _symbol) {
        manager = _manager;
        locked = false;
    }

    modifier onlyGuardian() {
        assert(guardian == msg.sender || owner() == msg.sender);
        _;
    }

    modifier unlocked() {
        if (locked) revert Locked();
        _;
    }

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;

        emit GuardianWasUpdated(guardian);
    }

    function toggleLock(bool _locked) external onlyGuardian {
        locked = _locked;

        emit LockWasToggled(locked);
    }
}
