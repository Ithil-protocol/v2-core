// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { CreditService } from "../CreditService.sol";
import { Service } from "../Service.sol";
import { IService } from "../../interfaces/IService.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { Service } from "../Service.sol";

/// @title    Call option contract
/// @author   Ithil
/// @notice   A service to obtain a call option on ITHIL by boosting
contract CallOption is CreditService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IVault;

    // It would be very hard to make a multi-token call option and ensuring consistency between prices
    // Therefore we make a single-token call option with a dutch auction price scheme
    // Price has precision of the underlying token
    // Total price is initialPrice + latestSpread
    // initialPrice is fixed, latestSpread follows a Dutch auction model
    uint256 public latestSpread;
    uint256 public latestOpen;
    uint256 public halvingTime;
    uint256 public totalAllocation;

    // This is the initial price, below which the token price cannot go
    // Beware that the actual minimum price is HALF the initial price
    // This is because locking liquidity for 1y will give a 50% discount
    uint256 public immutable initialPrice;
    uint256 public immutable tenorDuration;
    uint256 public immutable vestingTime;
    IERC20 public immutable underlying;
    IERC20 public immutable ithil;

    // 2^((n+1)/12) with 18 digit fixed point
    // this contract assumes ithil token has 18 decimals
    uint64[] internal _rewards;
    address internal immutable _vaultAddress;

    error ZeroAmount();
    error LockPeriodStillActive();
    error MaxLockExceeded();
    error MaxPurchaseExceeded();
    error InvalidIthilToken();
    error InvalidUnderlyingToken();
    error InvalidCalledPortion();
    error SlippageExceeded();
    error StillVested();

    // Since the maximum lock is 1 year, the deadline is 1 year + one month
    // (By convention, a month is 30 days, therefore the actual deadline is 5 to 7 days less)
    // This means that the tenor duration must be at most one month or the contract would break
    constructor(
        address _manager,
        address _ithil,
        uint256 _initialPrice,
        uint256 _halvingTime,
        uint256 _tenorDuration,
        uint256 _initialVesting,
        address _underlying
    )
        Service(
            string(abi.encodePacked("Ithil Senior Call Option - ", IERC20Metadata(_underlying).name())),
            string(abi.encodePacked("SCALL-", IERC20Metadata(_underlying).symbol())),
            _manager,
            13 * 30 * 86400
        )
    {
        assert(_initialPrice > 0);

        initialPrice = _initialPrice;
        underlying = IERC20(_underlying);
        ithil = IERC20(_ithil);
        halvingTime = _halvingTime;
        tenorDuration = _tenorDuration;
        vestingTime = _initialVesting + block.timestamp;

        _vaultAddress = manager.vaults(_underlying);
        // approve vault to spend underlying token for deposits
        // technically, it should be re-approved if the total volume exceeds 2^256
        // in practice, this event never happens, and in case just redeploy the service
        underlying.approve(_vaultAddress, type(uint256).max);

        _rewards = new uint64[](12);
        _rewards[0] = 1059463094359295265;
        _rewards[1] = 1122462048309372981;
        _rewards[2] = 1189207115002721067;
        _rewards[3] = 1259921049894873165;
        _rewards[4] = 1334839854170034365;
        _rewards[5] = 1414213562373095049;
        _rewards[6] = 1498307076876681499;
        _rewards[7] = 1587401051968199475;
        _rewards[8] = 1681792830507429086;
        _rewards[9] = 1781797436280678609;
        _rewards[10] = 1887748625363386993;
        _rewards[11] = 2000000000000000000;
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        // This is a credit service with one extra token, Ithil
        // therefore, the collateral length is 2

        if (agreement.loans[0].token != address(underlying)) revert InvalidUnderlyingToken();
        if (agreement.collaterals[1].token != address(ithil)) revert InvalidIthilToken();
        if (agreement.loans[0].amount == 0) revert ZeroAmount();

        uint256 price = _currentPrice();
        // Apply reward based on lock
        uint256 durationsLocked = abi.decode(data, (uint256));
        if (durationsLocked > 11) revert MaxLockExceeded();
        // unlock must occur after vesting
        if (block.timestamp + (durationsLocked + 1) * tenorDuration < vestingTime) revert StillVested();

        // we conventionally put the agreement's creation date as t0 - deadline + locking + 1
        // in this way, the expiry day is equal to the maturity of the option plus one month
        // therefore, the user will have 1 month to autonomously exercise or withdraw the option after expiry
        // after that, the position will be liquidated
        agreement.createdAt = block.timestamp + (durationsLocked + 2) * tenorDuration - deadline;

        // The amount bought if no price update were applied
        uint256 virtualBoughtAmount = (agreement.loans[0].amount * _rewards[durationsLocked]) / price;
        // Update current price based on the current balance and the collateral amount
        // One cannot purchase more than the total allocation
        if (totalAllocation <= virtualBoughtAmount) revert MaxPurchaseExceeded();

        // Update latest open and latest spread
        latestOpen = block.timestamp;
        // Total price increases as a function of the remaining allocation in inverse proportionality
        // E.g. if 50% of the entire allocation is bought, the current price gets multiplied by 2
        // if 10% of the allocation is bought, remaining is 9/10 so price gets multiplied by 10/9, etc...
        // notice that the denominator is positive since totalAllocation > virtualBoughtAmount
        latestSpread = (price * totalAllocation) / (totalAllocation - virtualBoughtAmount) - initialPrice;

        // We register the amount of ITHIL to be redeemed as collateral
        // The user obtains a discount based on how many months the position is locked
        uint256 collateral = ((agreement.loans[0].amount * _rewards[durationsLocked]) / (initialPrice + latestSpread));

        uint256 shares = IVault(_vaultAddress).convertToShares(agreement.loans[0].amount);
        if (collateral < agreement.collaterals[1].amount || shares < agreement.collaterals[0].amount) {
            revert SlippageExceeded();
        }

        agreement.collaterals[0].amount = shares;
        agreement.collaterals[1].amount = collateral;
        // update allocation: since we cannot know how much will be called, we subtract max
        // since collateral <= totalAllocation, this subtraction does not underflow
        totalAllocation -= collateral;

        // Deposit tokens to the relevant vault and register obtained amount
        IVault(_vaultAddress).deposit(agreement.loans[0].amount, address(this));
    }

    // the following must have a reentrancy guard since we do not have token minting
    // therefore we do not have any state variable which prevents an attacker from continuously losing
    // and continuously being refunded by the vault until the min(vaultLiquidity, thisLiquidity) is drained
    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual override {
        // The position can be closed only after the locking period
        if (block.timestamp < agreement.createdAt + deadline - tenorDuration) revert LockPeriodStillActive();
        // The portion of the loan amount we want to call
        // If the position is liquidable, we enforce the option not to be exercised
        uint256 calledPortion = abi.decode(data, (uint256));
        address ownerAddress = ownerOf(tokenID);
        if (calledPortion > 1e18 || (msg.sender != ownerAddress && calledPortion > 0)) revert InvalidCalledPortion();

        // redeem mechanism
        IVault vault = IVault(manager.vaults(agreement.loans[0].token));
        // calculate the amount of shares to redeem to get dueAmount
        uint256 toCall = (agreement.collaterals[1].amount * calledPortion) / 1e18;
        // The amount of ithil not called can be added back to the total allocation
        totalAllocation += (agreement.collaterals[1].amount - toCall);
        uint256 toTransfer = dueAmount(agreement, data);
        uint256 toRedeem = vault.convertToShares(toTransfer);
        uint256 transfered = vault.convertToAssets(
            toRedeem < agreement.collaterals[0].amount ? toRedeem : agreement.collaterals[0].amount
        );
        uint256 toBorrow;
        uint256 freeLiquidity;
        // If the called portion is not 100%, there are residual tokens which are transferred to the treasury
        if (toRedeem < agreement.collaterals[0].amount) {
            vault.safeTransfer(owner(), agreement.collaterals[0].amount - toRedeem);
        }
        // redeem the user's tokens and give the proceedings back to the user
        vault.redeem(
            toRedeem < agreement.collaterals[0].amount ? toRedeem : agreement.collaterals[0].amount,
            ownerAddress,
            address(this)
        );
        if (toTransfer > transfered) {
            // Since this service is senior, we need to pay the user even if withdraw amount is too low
            // To do this, we take liquidity from the vault and register the loss
            // If we incur a loss and the freeLiquidity is not enough, we cannot make the exit fail
            // Otherwise we would have positions impossible to close: thus we withdraw what we can
            freeLiquidity = vault.freeLiquidity() - 1;
            toBorrow = toTransfer - transfered > freeLiquidity ? freeLiquidity : toTransfer - transfered;
        }
        // We will always have ithil.balanceOf(address(this)) >= toCall, so the following succeeds
        ithil.safeTransfer(ownerAddress, toCall);
        // repay the user's losses
        if (toBorrow > 0 && freeLiquidity > 0) manager.borrow(agreement.loans[0].token, toBorrow, 0, ownerAddress);
    }

    function _currentPrice() internal view returns (uint256) {
        return
            block.timestamp < 2 * halvingTime + latestOpen
                ? initialPrice + (latestSpread * (2 * halvingTime + latestOpen - block.timestamp)) / (2 * halvingTime)
                : initialPrice;
    }

    function currentPrice() public view returns (uint256) {
        return _currentPrice();
    }

    function dueAmount(Agreement memory agreement, bytes memory data) public view virtual override returns (uint256) {
        // The portion of the loan amount we want to call
        uint256 calledPortion = abi.decode(data, (uint256));

        // The non-called portion is capital to give back to the user
        return (agreement.loans[0].amount * (1e18 - calledPortion)) / 1e18;
    }

    function allocateIthil(uint256 amount) external {
        totalAllocation += amount;
        ithil.safeTransferFrom(msg.sender, address(this), amount);
    }

    function sweepIthil() external onlyOwner {
        // Only total allocation can be swept, otherwise there would be a risk of rug pull
        // in case owner sweeps balance when there are still open orders
        uint256 initialAllocation = totalAllocation;
        totalAllocation = 0;
        ithil.safeTransfer(msg.sender, initialAllocation);
    }
}
