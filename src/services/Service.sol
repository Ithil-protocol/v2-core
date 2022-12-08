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
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract Service is IService, ERC721Enumerable, Ownable {
    using GeneralMath for uint256;
    uint256 internal constant RESOLUTION = 1e18;
    uint256 internal constant oneYear = 1 years;
    enum ItemType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Item {
        ItemType itemType;
        address token;
        uint256 identifier; // what is this?
        uint256 amount;
    }

    struct BaseAgreement {
        Item owed;
        Item obtained;
        address lender;
        uint256 interestRate;
        uint256 createdAt;
    }

    IManager public immutable manager;
    bytes32 internal immutable salt;
    address public guardian;
    bool public locked;
    IInterestRateModel public interestRateModel;
    mapping(uint256 => BaseAgreement) public agreements;
    mapping(address => uint256) public riskSpread; // asset => risk spread value (if 0 -> not supported)

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

    function setRiskSpread(address asset, uint256 newValue) external onlyOwner {
        riskSpread[asset] = newValue;

        emit RiskSpreadWasUpdated(asset, newValue);
    }

    // Should be setup in the constructor? A service with no IR seems ill-defined
    function setInterestRateModel(address newInterestRateModel) external onlyOwner {
        interestRateModel = IInterestRateModel(newInterestRateModel);

        emit InterestRateModelWasUpdated(newInterestRateModel);
    }

    function enter(bytes calldata order) external virtual unlocked {}

    function exit(bytes calldata order) external virtual {}

    function calculateFees(uint256 id) public view returns (uint256) {
        agreements[id].amount.safeMulDiv(agreements[id].interestRate, RESOLUTION).safeMulDiv(
            block.timestamp - agreements[id].createdAt,
            oneYear
        );
    }

    // Why would you want the Vault if who gets the funds is the lender (already in BaseAgreement)?
    // This would also avoid the need of the salt
    function getVault(address asset) internal view returns (address) {
        return
            Create2.computeAddress(
                salt,
                keccak256(abi.encodePacked(type(Vault).creationCode, abi.encode(IERC20Metadata(asset)))),
                address(manager)
            );
    }
}
