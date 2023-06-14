// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Service } from "./Service.sol";
import { BaseRiskModel } from "./BaseRiskModel.sol";

abstract contract DebitService is Service, BaseRiskModel {
    using SafeERC20 for IERC20;

    error MarginTooLow();

    uint256 internal constant _ONE_YEAR = 31536000;
    uint256 internal constant _RESOLUTION = 1e18;

    mapping(address => uint256) public minMargin;

    function setMinMargin(address token, uint256 margin) external onlyOwner {
        minMargin[token] = margin;
    }

    /// @dev Defaults to amount + margin * riskSpread / (ir + riskSpread)
    function _liquidationThreshold(uint256 amount, uint256 margin, uint256 interestAndSpread)
        internal
        view
        virtual
        returns (uint256)
    {
        // In a zero-risk case, we just liquidate when the loan amount is reached
        if (interestAndSpread == 0) return amount;
        (uint256 interestRate, uint256 riskSpread) = (interestAndSpread >> 128, interestAndSpread % (1 << 128));
        // at this point, we are not dividing by zero
        return amount + (margin * riskSpread) / (interestRate + riskSpread);
    }

    /// @dev This function defaults to positive if and only if at least one of the quoted values
    /// is less than liquidationThreshold
    /// @dev it MUST be such that a liquidable agreement has liquidationScore > 0
    function liquidationScore(uint256 id) public view virtual returns (uint256) {
        Agreement memory agreement = agreements[id];
        uint256[] memory quotes = quote(agreement);
        uint256[] memory fees = computeDueFees(agreement);

        uint256 score = 0;
        for (uint256 index = 0; index < quotes.length; index++) {
            uint256 minimumQuote = _liquidationThreshold(
                agreement.loans[index].amount,
                agreement.loans[index].margin,
                agreement.loans[index].interestAndSpread
            ) + fees[index];
            score = minimumQuote > quotes[index] ? score + (minimumQuote - quotes[index]) : score;
        }

        return score;
    }

    function open(Order calldata order) public virtual override unlocked {
        // Transfers margins and borrows loans to this address
        Agreement memory agreement = order.agreement;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            if (agreement.loans[index].margin < minMargin[agreement.loans[index].token]) revert MarginTooLow();
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
                agreement.loans[index].amount,
                address(this)
            );

            _checkRiskiness(agreement.loans[index], freeLiquidity);
        }
        Service.open(order);
    }

    function close(uint256 tokenID, bytes calldata data) public virtual override returns (uint256[] memory amountsOut) {
        Agreement memory agreement = agreements[tokenID];
        address owner = ownerOf(tokenID);
        if (owner != msg.sender && liquidationScore(tokenID) == 0 && agreement.createdAt + deadline > block.timestamp)
            revert RestrictedToOwner();

        uint256[] memory obtained = new uint256[](agreement.loans.length);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            obtained[index] = IERC20(agreement.loans[index].token).balanceOf(address(this));
        }
        Service.close(tokenID, data);

        uint256[] memory dueFees = computeDueFees(agreement);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            obtained[index] = IERC20(agreement.loans[index].token).balanceOf(address(this)) - obtained[index];
            if (obtained[index] > dueFees[index] + agreement.loans[index].amount) {
                IERC20(agreement.loans[index].token).approve(
                    manager.vaults(agreement.loans[index].token),
                    dueFees[index] + agreement.loans[index].amount
                );
                // Good repay: the difference is transferred to the user
                manager.repay(
                    agreement.loans[index].token,
                    dueFees[index] + agreement.loans[index].amount,
                    agreement.loans[index].amount,
                    address(this)
                );
                IERC20(agreement.loans[index].token).safeTransfer(
                    owner,
                    obtained[index] - (dueFees[index] + agreement.loans[index].amount)
                );
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
    function quote(Agreement memory agreement) public view virtual returns (uint256[] memory);

    // Computes the payment due to the vault or lender
    // Defaults with loan * (1 + IR * time)
    function computeDueFees(Agreement memory agreement) public view virtual returns (uint256[] memory) {
        uint256[] memory dueFees = new uint256[](agreement.loans.length);
        for (uint256 i = 0; i < agreement.loans.length; i++) {
            (uint256 base, uint256 spread) = (
                agreement.loans[i].interestAndSpread >> 128,
                agreement.loans[i].interestAndSpread % (1 << 128)
            );
            dueFees[i] =
                (agreement.loans[i].amount * ((base + spread) * (block.timestamp - agreement.createdAt))) /
                (_RESOLUTION * _ONE_YEAR);
        }
        return dueFees;
    }
}
