// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC4626, IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IVault } from "./interfaces/IVault.sol";

// Since this vault inherits from ERC4626, it has the known vulnerability of the "donation attack"
// In the Ithil framework this is fixed by deploying the Vault already with 1 token deposited
// This means that both the balance and the supply are at least 1 every time
contract Vault is IVault, ERC4626, ERC20Permit {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public immutable manager;
    uint256 public immutable override creationTime;
    uint256 public override feeUnlockTime;
    uint256 public override netLoans;
    uint256 public override latestRepay;
    uint256 public override currentProfits;
    uint256 public override currentLosses;
    bool public override isLocked;

    constructor(
        IERC20Metadata _token
    )
        ERC20(string(abi.encodePacked("Ithil ", _token.name())), string(abi.encodePacked("i", _token.symbol())))
        ERC20Permit(string(abi.encodePacked("Ithil ", _token.name())))
        ERC4626(_token)
    {
        manager = msg.sender;
        creationTime = block.timestamp;
        feeUnlockTime = 21600; // six hours
    }

    modifier onlyOwner() {
        if (manager != msg.sender) revert RestrictedToOwner();
        _;
    }

    modifier unlocked() {
        if (isLocked) revert Locked();
        _;
    }

    function decimals() public view override(IERC20Metadata, ERC4626, ERC20) returns (uint8) {
        return ERC4626.decimals();
    }

    function toggleLock() external override onlyOwner {
        isLocked = !isLocked;

        emit LockToggled(isLocked);
    }

    function setFeeUnlockTime(uint256 _feeUnlockTime) external override onlyOwner {
        // Minimum 30 seconds, maximum 7 days
        // This also avoids division by zero in _calculateLockedProfits()
        if (_feeUnlockTime < 30 seconds || _feeUnlockTime > 7 days) revert FeeUnlockTimeOutOfRange();
        feeUnlockTime = _feeUnlockTime;

        emit DegradationCoefficientWasUpdated(feeUnlockTime);
    }

    function sweep(address to, address token) external onlyOwner {
        assert(token != asset());

        IERC20 spuriousToken = IERC20(token);
        spuriousToken.safeTransfer(to, spuriousToken.balanceOf(address(this)));
    }

    function getFeeStatus() external view override returns (uint256, uint256, uint256, uint256) {
        return (currentProfits, currentLosses, feeUnlockTime, latestRepay);
    }

    function getLoansAndLiquidity() external view override returns (uint256, uint256) {
        return (netLoans, freeLiquidity());
    }

    // Total assets are used to calculate shares to mint and redeem
    // They represent the deposited amount, the loans and the unlocked fees
    // As per ERC4626 standard this must never throw
    // super.totalAssets() - _calculateLockedProfits() <= IERC20(asset()).totalSupply() - netLoans so no overflow
    // _calculateLockedProfits() <= currentProfits <= super.totalAssets() so no underflow
    // totalAssets() must adjust so that maxWithdraw() is an invariant for all functions
    // As profits unlock, assets increase or decrease
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return (super.totalAssets() - _calculateLockedProfits()) + netLoans + _calculateLockedLosses();
    }

    // Free liquidity available to withdraw or borrow
    // Locked profits are locked for every operation
    // We do not consider negative profits since they are not true liquidity
    // We subtract 1 because there is always 1 token deposited at the beginning: this will never be taken
    function freeLiquidity() public view override returns (uint256) {
        return super.totalAssets() - _calculateLockedProfits();
    }

    // Assets include netLoans but they are not available for withdraw
    // Therefore we need to cap with the current free liquidity
    function maxWithdraw(address owner) public view override(ERC4626, IERC4626) returns (uint256) {
        uint256 freeLiq = freeLiquidity();
        uint256 supply = totalSupply();
        uint256 shares = balanceOf(owner);
        // super.maxWithdraw but we leverage the fact of having already computed freeLiq which contains balanceOf()
        // notice that shares are always at least 1
        return freeLiq.min(shares.mulDiv(freeLiq + netLoans + _calculateLockedLosses(), supply));
    }

    // Assets include netLoans but they are not available for withdraw
    // Therefore we need to cap with the current free liquidity
    function maxRedeem(address owner) public view override(ERC4626, IERC4626) returns (uint256) {
        uint256 maxRedeemCache = balanceOf(owner);
        uint256 freeLiquidityCache = super.totalAssets() - _calculateLockedProfits();
        uint256 totalAssetsCache = freeLiquidityCache + netLoans + _calculateLockedLosses();
        uint256 supply = totalSupply();
        // convertToAssets but we leverage the fact of having already computed totalAssetsCache
        // we need to compute it separately because we use freeLiquidityCache later
        // in this way, the entire function has only one call to balanceOf()
        uint256 assets = maxRedeemCache.mulDiv(totalAssetsCache, supply);

        // convertToShares using the already computed variables
        // if the assets the owner can theoretically withdraw are higher than the free liquidity
        // we cap them with the convertToShares of the free liquidity
        if (assets >= freeLiquidityCache && assets > 0) {
            maxRedeemCache = freeLiquidityCache.mulDiv(supply, totalAssetsCache);
        }

        return maxRedeemCache;
    }

    function mint(uint256 shares, address receiver) public override(IERC4626, ERC4626) unlocked returns (uint256) {
        return ERC4626.mint(shares, receiver);
    }

    function deposit(uint256 _assets, address receiver) public override(IERC4626, ERC4626) unlocked returns (uint256) {
        return ERC4626.deposit(_assets, receiver);
    }

    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external unlocked returns (uint256) {
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);

        return deposit(assets, receiver);
    }

    // Throws 'ERC20: transfer amount exceeds balance
    // IERC20(asset()).balanceOf(address(this)) < assets
    // Needs approvals if caller is not owner
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626, IERC4626) returns (uint256) {
        // assets cannot be more than the current free liquidity
        uint256 freeLiq = freeLiquidity();
        if (assets >= freeLiq) revert InsufficientLiquidity();

        // super.withdraw but we leverage the fact of having already computed freeLiq
        uint256 supply = totalSupply();

        // assets > 0 and supply > 0 always
        uint256 shares = assets.mulDiv(supply, freeLiq + netLoans + _calculateLockedLosses());
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    // Needs approvals if caller is not owner
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626, IERC4626) returns (uint256) {
        uint256 freeLiq = freeLiquidity();
        uint256 totalAssetsCache = freeLiq + netLoans + _calculateLockedLosses();
        // previewRedeem, leveraging the fact of having already computed freeLiq
        uint256 supply = totalSupply();

        uint256 assets = shares.mulDiv(totalAssetsCache, supply);
        if (assets >= freeLiq) revert InsufficientLiquidity();
        // redeem, now all data have been computed
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    // Owner is the only trusted borrower
    // Invariant: totalAssets()
    function borrow(
        uint256 assets,
        uint256 loan,
        address receiver
    ) external override unlocked onlyOwner returns (uint256, uint256) {
        // We do not allow loans higher than the assets: borrowing cannot generate profits
        // This prevents overflow in totalAssets() and netLoans
        // And makes totalAssets() a sub-invariant of this function
        if (loan > assets) revert LoanHigherThanAssetsInBorrow();
        uint256 freeLiq = freeLiquidity();

        if (assets >= freeLiq) revert InsufficientFreeLiquidity();

        netLoans += loan;
        currentProfits = _calculateLockedProfits();
        currentLosses = _calculateLockedLosses() + (assets - loan);
        latestRepay = block.timestamp;

        IERC20(asset()).safeTransfer(receiver, assets);

        emit Borrowed(receiver, assets);

        return (freeLiq, netLoans);
    }

    // Owner is the only trusted repayer
    // Transfers assets from repayer to the vault
    // assets amount may be greater or less than debt
    // Reverts if the repayer did not approve the vault
    // Reverts if the repayer does not have the specified number of assets
    // _calculateLockedProfits() = currentProfits immediately after
    // Invariant: totalAssets()
    // maxWithdraw() is invariant as long as totalAssets()-currentProfits >= native.balanceOf(this)
    function repay(uint256 assets, uint256 debt, address repayer) external override onlyOwner {
        uint256 initialLoans = netLoans;
        debt = debt.min(initialLoans);
        netLoans -= debt;

        // Since assets are transferred, this is always less than totalSupply() so no overflow
        if (assets > debt) {
            currentProfits = _calculateLockedProfits() + (assets - debt);
            currentLosses = _calculateLockedLosses();
        }
        // Since debt was transferred from vault, this is always less than totalSupply() so no overflow
        else {
            currentProfits = _calculateLockedProfits();
            currentLosses = _calculateLockedLosses() + (debt - assets);
        }
        latestRepay = block.timestamp;

        // the vault is not responsible for any payoff
        // slither-disable-next-line arbitrary-send-erc20
        // super.totalAssets() += assets and never overflows by definition
        IERC20(asset()).safeTransferFrom(repayer, address(this), assets);

        emit Repaid(repayer, assets, debt);
    }

    // Starts from currentProfits and go linearly to 0
    // It is zero when block.timestamp-latestRepay > feeUnlockTime
    function _calculateLockedProfits() internal view returns (uint256) {
        return currentProfits.mulDiv(feeUnlockTime - (block.timestamp - latestRepay).min(feeUnlockTime), feeUnlockTime);
    }

    // Starts from currentLosses and go linearly to 0
    // It is zero when block.timestamp-latestRepay > feeUnlockTime
    function _calculateLockedLosses() internal view returns (uint256) {
        return currentLosses.mulDiv(feeUnlockTime - (block.timestamp - latestRepay).min(feeUnlockTime), feeUnlockTime);
    }
}
