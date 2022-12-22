// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    using GeneralMath for uint256;

    /// @dev Defaults to riskSpread = baseRiskSpread * amount / margin
    /// Throws if margin = 0
    function riskSpreadFromMargin(uint256 amount, uint256 margin, uint256 baseSpread)
        internal
        view
        virtual
        returns (uint256)
    {
        return baseSpread.safeMulDiv(amount, margin);
    }

    /// @dev Defaults to amount + margin * riskSpread / (ir + riskSpread)
    function liquidationThreshold(uint256 amount, uint256 margin, uint256 interestAndSpread)
        internal
        view
        virtual
        returns (uint256)
    {
        (uint256 interestRate, uint256 riskSpread) = interestAndSpread.unpackUint();
        return amount.safeAdd(margin.safeMulDiv(riskSpread, interestRate + riskSpread));
    }

    /// @dev This function defaults to positive if and only if at least one of the quoted values
    /// is less than liquidationThreshold
    /// @dev it MUST be such that a liquidable agreement has liquidationScore > 0
    function liquidationScore(uint256 id) public view virtual returns (uint256) {
        Agreement memory agreement = agreements[id];
        (uint256[] memory quotes, uint256[] memory fees) = quote(agreement);

        uint256 score = 0;
        for (uint256 index = quotes.length; index > 0; index--) {
            uint256 minimumQuote = liquidationThreshold(
                agreement.loans[index].amount,
                agreement.loans[index].margin,
                agreement.loans[index].interestAndSpread
            ).safeAdd(fees[index]);
            score = score.safeAdd(minimumQuote.positiveSub(quotes[index]));
        }

        return score;
    }

    /// @dev When quoting we need to return values for all owed items
    /// how: for first to last index, calculate minimum obtained >= loan amount + fees
    function quote(Agreement memory agreement) public view virtual returns (uint256[] memory, uint256[] memory);
}
