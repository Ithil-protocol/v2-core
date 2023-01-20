// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    error Too_Risky();

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

    function open(Order calldata order) public virtual override unlocked {
        // Transfers margins and borrows loans to this address
        Agreement memory agreement = order.agreement;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            exposures[agreement.loans[index].token] += agreement.loans[index].amount;
            IERC20(agreement.loans[index].token).safeTransferFrom(
                msg.sender,
                address(this),
                agreement.loans[index].margin
            );
            (uint256 freeLiquidity, ) = manager.borrow(
                agreement.loans[index].token,
                agreement.loans[index].amount,
                exposures[agreement.loans[index].token],
                address(this)
            );

            (uint256 computedIR, uint256 computedSpread) = _baseInterestRateAndSpread(agreement, freeLiquidity);
            (uint256 requestedIR, uint256 requestedSpread) = agreement.loans[index].interestAndSpread.unpackUint();
            if (computedIR > requestedIR || computedSpread > requestedSpread) revert Too_Risky();
        }

        super.open(order);
    }

    function close(uint256 tokenID, bytes calldata data) public virtual override {
        if (ownerOf(tokenID) != msg.sender && liquidationScore(tokenID) == 0) revert RestrictedToOwner();

        super.close(tokenID, data);

        Agreement memory agreement = agreements[tokenID];
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            exposures[agreement.loans[index].token] = exposures[agreement.loans[index].token].positiveSub(
                agreement.loans[index].amount
            );

            manager.repay(
                agreement.loans[index].token,
                _computeDuePayment(agreement, data),
                agreement.loans[index].amount,
                address(this)
            );
        }
    }

    /// @dev When quoting we need to return values for all owed items
    /// how: for first to last index, calculate minimum obtained >= loan amount + fees
    function quote(Agreement memory agreement) public view virtual returns (uint256[] memory, uint256[] memory);

    function _baseInterestRateAndSpread(Agreement memory agreement, uint256 freeLiquidity)
        internal
        virtual
        returns (uint256, uint256)
    {}

    // Computes the payment due to the vault or lender
    function _computeDuePayment(Agreement memory agreement, bytes calldata data) internal virtual returns (uint256) {}
}
