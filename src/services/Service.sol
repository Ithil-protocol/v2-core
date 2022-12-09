// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IService } from "../interfaces/IService.sol";
import { IManager } from "../interfaces/IManager.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { Vault } from "../Vault.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
    using GeneralMath for uint256;

    enum ItemType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Item {
        ItemType itemType;
        address token;
        uint256 identifier;
        uint256 amount;
    }

    IInterestRateModel public immutable interestRateModel;
    IManager public immutable manager;
    address public guardian;
    bool public locked;
    // token => tokenID (ERC721/1155) / 0 (ERC20) => risk spread value (if 0 then it is not supported)
    mapping(address => mapping(uint256 => uint256)) public riskSpread;

    constructor(string memory _name, string memory _symbol, address _interestRateModel, address _manager)
        ERC721(_name, _symbol)
    {
        interestRateModel = IInterestRateModel(_interestRateModel);
        manager = IManager(_manager);
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

    ///// Admin functions /////

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;

        emit GuardianWasUpdated(guardian);
    }

    function toggleLock(bool _locked) external onlyGuardian {
        locked = _locked;

        emit LockWasToggled(locked);
    }

    function setRiskSpread(address asset, uint256 id, uint256 newValue) external onlyOwner {
        riskSpread[asset][id] = newValue;

        emit RiskSpreadWasUpdated(asset, id, newValue);
    }

    ///// Service functions /////

    function enter(bytes calldata order) external virtual unlocked {}

    function exit(bytes calldata order) external virtual {}
}
