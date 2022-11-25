// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC721, ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IService } from "../interfaces/IService.sol";
import { IManager } from "../interfaces/IManager.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { Vault } from "../Vault.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
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

    IManager public immutable manager;
    bytes32 internal immutable salt;
    address public guardian;
    bool public locked;
    IInterestRateModel public interestRateModel;
    mapping(uint256 => address) public lender; // token ID => lender address
    mapping(address => uint256) public riskFactors; // asset => risk factor value (if 0 -> not supported)

    constructor(string memory _name, string memory _symbol, address _manager) ERC721(_name, _symbol) {
        manager = IManager(_manager);
        salt = manager.salt();
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

    function setRiskFactor(address asset, uint256 newValue) external onlyOwner {
        riskFactors[asset] = newValue;

        emit RiskFactorWasUpdated(asset, newValue);
    }

    function setInterestRateModel(address newInterestRateModel) external onlyOwner {
        interestRateModel = IInterestRateModel(newInterestRateModel);

        emit InterestRateModelWasUpdated(newInterestRateModel);
    }

    function enter(bytes calldata order) external virtual unlocked {}

    function exit(bytes calldata order) external virtual {}

    function getVault(address asset) internal view returns (address) {
        return Create2.computeAddress(
            salt,
            keccak256(abi.encodePacked(type(Vault).creationCode, abi.encode(IERC20Metadata(asset)))),
            address(manager)
        );
    }
}
