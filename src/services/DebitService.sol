// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Service } from "./Service.sol";
import { BaseRiskModel } from "./BaseRiskModel.sol";
import { RESOLUTION, ONE_YEAR } from "../Constants.sol";

abstract contract DebitService is Service, BaseRiskModel {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public minMargin;

    event LiquidationTriggered(uint256 indexed id, address token, address indexed liquidator, uint256 payoff);
    error MarginTooLow();

    function setMinMargin(address token, uint256 margin) external onlyOwner {
        minMargin[token] = margin;
    }

    /// @dev Defaults to amount + margin * (ir + riskSpread) / 1e18
    function _liquidationThreshold(
        uint256 amount,
        uint256 margin,
        uint256 interestAndSpread
    ) internal view virtual returns (uint256) {
        (uint256 interestRate, uint256 riskSpread) = (interestAndSpread >> 128, interestAndSpread % (1 << 128));
        // Any good interest rate model must have interestRate + riskSpread < RESOLUTION
        // otherwise a position may be instantly liquidable
        return amount + (margin * (interestRate + riskSpread)) / RESOLUTION;
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
            // minimumQuote = liquidationThreshold + fees
            uint256 minimumQuote = _liquidationThreshold(
                agreement.loans[index].amount,
                agreement.loans[index].margin,
                agreement.loans[index].interestAndSpread
            ) + fees[index];
            // The score is the sum of percentage negative displacements from the minimumQuotes
            score = minimumQuote > quotes[index]
                ? score + ((minimumQuote - quotes[index]) * RESOLUTION) / minimumQuote
                : score;
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
        uint256 score = liquidationScore(tokenID);
        if (owner != msg.sender && score == 0 && agreement.createdAt + deadline > block.timestamp)
            revert RestrictedToOwner();

        uint256[] memory obtained = new uint256[](agreement.loans.length);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            obtained[index] = IERC20(agreement.loans[index].token).balanceOf(address(this));
        }
        Service.close(tokenID, data);

        uint256[] memory dueFees = computeDueFees(agreement);
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            obtained[index] = IERC20(agreement.loans[index].token).balanceOf(address(this)) - obtained[index];
            // first repay the liquidator
            // the liquidation reward can never be higher than the margin
            // if the liquidable position is closed by its owner, it is *not* considered a liquidation event
            if (owner != msg.sender) {
                // This can either due to score > 0 or deadline exceeded
                // In the latter case, the fee is linear with time until reacing 5% in one month (31 days)
                // If a position is both liquidable and expired, liquidation has the priority
                uint256 liquidatorReward;
                if (score > 0) liquidatorReward = (agreement.loans[index].margin * score) / RESOLUTION;
                else {
                    // in this case agreement.createdAt + deadline <= block.timestamp
                    uint256 timeMaxOneMonth = block.timestamp - (deadline + agreement.createdAt) < 86400 * 31
                        ? block.timestamp - (deadline + agreement.createdAt)
                        : 86400 * 31;
                    liquidatorReward = (agreement.loans[index].margin * timeMaxOneMonth) / (86400 * 31 * 20);
                }
                // We cap further the liquidation reward with the obtained amount (no cross-position rewarding)
                // This also prevents the following transfer to revert
                liquidatorReward = liquidatorReward < obtained[index] ? liquidatorReward : obtained[index];
                IERC20(agreement.loans[index].token).safeTransfer(msg.sender, liquidatorReward);
                obtained[index] -= liquidatorReward;

                emit LiquidationTriggered(tokenID, agreement.loans[index].token, msg.sender, liquidatorReward);
            }

            // secondly repay the vault
            uint256 repaidAmount = obtained[index] > dueFees[index] + agreement.loans[index].amount
                ? dueFees[index] + agreement.loans[index].amount
                : obtained[index];

            IERC20(agreement.loans[index].token).approve(manager.vaults(agreement.loans[index].token), repaidAmount);
            manager.repay(agreement.loans[index].token, repaidAmount, agreement.loans[index].amount, address(this));

            // finally repay the owner
            IERC20(agreement.loans[index].token).safeTransfer(owner, obtained[index] - repaidAmount);
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
                (RESOLUTION * ONE_YEAR);
        }
        return dueFees;
    }
}
