// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Service } from "./Service.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GeneralMath } from "../libraries/GeneralMath.sol";

abstract contract DebitService is Service {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant ONE_YEAR = 31536000;

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
        for (uint256 index = 0; index < quotes.length; index++) {
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
            // No need to launch borrow if amount is zero
            uint256 freeLiquidity;
            (freeLiquidity, ) = manager.borrow(
                agreement.loans[index].token,
                agreement.loans[index].amount,
                exposures[agreement.loans[index].token],
                address(this)
            );

            _checkRiskiness(agreement.loans[index], freeLiquidity);
        }
        super.open(order);
    }

    function close(uint256 tokenID, bytes calldata data) public virtual override returns (uint256[] memory) {
        if (ownerOf(tokenID) != msg.sender && liquidationScore(tokenID) == 0) revert RestrictedToOwner();

        uint256[] memory obtained = super.close(tokenID, data);

        Agreement memory agreement = agreements[tokenID];
        uint256[] memory duePayments = _computeDuePayments(agreement, data);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            exposures[agreement.loans[index].token] = exposures[agreement.loans[index].token].positiveSub(
                agreement.loans[index].amount
            );
            if (obtained[index] > duePayments[index]) {
                IERC20(agreement.loans[index].token).approve(
                    manager.vaults(agreement.loans[index].token),
                    duePayments[index]
                );
                // Good repay: the difference is transferred to the user
                manager.repay(
                    agreement.loans[index].token,
                    duePayments[index],
                    agreement.loans[index].amount,
                    address(this)
                );
                IERC20(agreement.loans[index].token).safeTransfer(msg.sender, obtained[index] - duePayments[index]);
            } else {
                // Bad repay: all the obtained amount is given to the vault
                IERC20(agreement.loans[index].token).approve(
                    manager.vaults(agreement.loans[index].token),
                    obtained[index]
                );
                manager.repay(
                    agreement.loans[index].token,
                    obtained[index],
                    agreement.loans[index].amount,
                    address(this)
                );
            }
        }
        return obtained;
    }

    /// @dev When quoting we need to return values for all owed items
    /// how: for first to last index, calculate minimum obtained >= loan amount + fees
    function quote(Agreement memory agreement) public view virtual returns (uint256[] memory, uint256[] memory) {}

    // Computes the payment due to the vault or lender
    // Defaults with loan * (1 + IR * time)
    function _computeDuePayments(Agreement memory agreement, bytes calldata /*data*/)
        internal
        virtual
        returns (uint256[] memory)
    {
        uint256[] memory duePayments = new uint256[](agreement.loans.length);
        for (uint256 i = 0; i < agreement.loans.length; i++) {
            (uint256 base, uint256 spread) = GeneralMath.unpackUint(agreement.loans[i].interestAndSpread);
            duePayments[i] = agreement.loans[i].amount.safeMulDiv(
                (base + spread) * (block.timestamp - agreement.createdAt),
                GeneralMath.RESOLUTION * ONE_YEAR
            );
            duePayments[i] += agreement.loans[i].amount;
        }
        return duePayments;
    }

    // Checks the riskiness of the agreement and eventually reverts with AboveRiskThreshold()
    function _checkRiskiness(Loan memory loan, uint256 freeLiquidity) internal virtual {}
}
