// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    using GeneralMath for uint256;
    // token => tokenID (ERC721/1155) / 0 (ERC20) => risk spread value (if 0 then it is not supported)
    mapping(address => mapping(uint256 => uint256)) public baseRiskSpread;

    constructor(string memory _name, string memory _symbol, address _manager, address _interestRateModel)
        Service(_name, _symbol, _manager, _interestRateModel)
    {}

    function setBaseRiskSpread(address asset, uint256 id, uint256 newValue) external onlyOwner {
        baseRiskSpread[asset][id] = newValue;

        emit BaseRiskSpreadWasUpdated(asset, id, newValue);
    }

    // This function is positive if and only if at least one of the quoted values
    // is less than amount + margin * riskSpread / (ir + riskSpread)
    // Assumes riskSpread = baseRiskSpread * amount / margin
    function liquidationScore(uint256 id) public returns (uint256) {
        (uint256[] memory quotes, ) = quote(id);
        Agreement memory agreement = agreements[id];
        uint256 score = 0;
        for (uint256 index = 0; index < quotes.length; index++) {
            (uint256 interestRate, uint256 riskSpread) = agreement.loans[index].interestAndSpread.unpackUint();
            uint256 adjustedLoan = agreement.loans[index].amount.safeMulDiv(
                baseRiskSpread[agreement.loans[index].token][agreement.obtained[index].identifier] +
                    interestRate +
                    riskSpread,
                interestRate + riskSpread
            );
            score += adjustedLoan.positiveSub(quotes[index]);
        }
        return score;
    }

    // When quoting we need to return values for all owed items
    // Algorithm: for first to last index, calculate minimum obtained >= loan amount + fees
    function quote(uint256 id) public virtual returns (uint256[] memory, uint256[] memory);
}
