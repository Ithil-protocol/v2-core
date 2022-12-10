// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    // Owed is forcefully ERC20: the Manager only deals with current ERC4626 Vault and vault.asset() is ERC20
    struct Loan {
        address token;
        uint256 amount;
        uint256 interestAndSpread;
    }

    struct DebitAgreement {
        Loan[] loans;
        Item[] obtained;
        address lender;
        uint256 createdAt;
    }

    mapping(uint256 => DebitAgreement) public agreements;
    IInterestRateModel public immutable interestRateModel;
    // token => tokenID (ERC721/1155) / 0 (ERC20) => risk spread value (if 0 then it is not supported)
    mapping(address => mapping(uint256 => uint256)) public baseRiskSpread;

    constructor(string memory _name, string memory _symbol, address _interestRateModel, address _manager)
        Service(_name, _symbol, _manager)
    {
        interestRateModel = IInterestRateModel(_interestRateModel);
    }

    function setBaseRiskSpread(address asset, uint256 id, uint256 newValue) external onlyOwner {
        baseRiskSpread[asset][id] = newValue;

        emit BaseRiskSpreadWasUpdated(asset, id, newValue);
    }

    function liquidationScore(uint256 id) public virtual returns (uint256);

    // When quoting we need to return values and fees for all owed items
    function quote(uint256 id) public virtual returns (uint256[] memory, uint256[] memory);
}
