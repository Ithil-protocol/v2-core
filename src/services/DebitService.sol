// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    using GeneralMath for uint256;
    // token => tokenID (ERC721/1155) / 0 (ERC20) => risk spread value (if 0 then it is not supported)
    mapping(address => mapping(uint256 => uint256)) public baseRiskSpread;

    function setBaseRiskSpread(address asset, uint256 id, uint256 newValue) external onlyOwner {
        baseRiskSpread[asset][id] = newValue;

        emit BaseRiskSpreadWasUpdated(asset, id, newValue);
    }

    /// @dev Defaults to riskSpread = baseRiskSpread * amount / margin
    /// Throws if margin = 0
    function riskSpreadFromMargin(uint256 amount, uint256 margin, uint256 baseSpread)
        internal
        virtual
        returns (uint256)
    {
        return baseSpread.safeMulDiv(amount, margin);
    }

    /// Throws if riskSpread = 0
    function marginFromRiskSpread(uint256 amount, uint256 baseSpread, uint256 riskSpread)
        internal
        virtual
        returns (uint256)
    {
        return amount.safeMulDiv(baseSpread, riskSpread);
    }

    /// Defaults to amount + margin * riskSpread / (ir + riskSpread)
    function liquidationThreshold(uint256 amount, uint256 baseSpread, uint256 interestAndSpread)
        internal
        virtual
        returns (uint256)
    {
        (uint256 interestRate, uint256 riskSpread) = interestAndSpread.unpackUint();
        uint256 margin = marginFromRiskSpread(amount, baseSpread, riskSpread);
        return amount.safeAdd(margin.safeMulDiv(riskSpread, interestRate + riskSpread));
    }

    // This function is positive if and only if at least one of the quoted values
    // is less than liquidationThreshold
    function liquidationScore(uint256 id) public returns (uint256) {
        Agreement memory agreement = agreements[id];
        (uint256[] memory quotes, uint256[] memory fees) = quote(agreement);

        uint256 score = 0;
        for (uint256 index = 0; index < quotes.length; index++) {
            uint256 minimumQuote = liquidationThreshold(
                agreement.loans[index].amount,
                baseRiskSpread[agreement.loans[index].token][agreement.obtained[index].identifier],
                agreement.loans[index].interestAndSpread
            ).safeAdd(fees[index]);
            score = score.safeAdd(minimumQuote.positiveSub(quotes[index]));
        }

        return score;
    }

    // When quoting we need to return values for all owed items
    // Algorithm: for first to last index, calculate minimum obtained >= loan amount + fees
    function quote(Agreement memory agreement) public virtual returns (uint256[] memory, uint256[] memory);
}
