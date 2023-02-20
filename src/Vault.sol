// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC4626, IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { GeneralMath } from "./libraries/GeneralMath.sol";
import { IVault } from "./interfaces/IVault.sol";

contract Vault is IVault, ERC4626, ERC20Permit {
    using GeneralMath for uint256;
    using GeneralMath for int256;
    using SafeERC20 for IERC20;

    address public immutable manager;
    uint256 public immutable override creationTime;
    uint256 public override feeUnlockTime;
    uint256 public override netLoans;
    uint256 public override latestRepay;
    uint256 public override currentProfits;
    uint256 public override currentLosses;

    constructor(IERC20Metadata _token)
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

    function decimals() public view override(IERC20Metadata, ERC4626, ERC20) returns (uint8) {
        return super.decimals();
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

    // Total assets are used to calculate shares to mint and redeem
    // They represent the deposited amount, the loans and the unlocked fees
    // As per ERC4626 standard this must never throw
    // super.totalAssets() - _calculateLockedProfits() <= IERC20(asset()).totalSupply() - netLoans so no overflow
    // _calculateLockedProfits() <= currentProfits <= super.totalAssets() so no underflow
    // totalAssets() must adjust so that maxWithdraw() is an invariant for all functions
    // As profits unlock, assets increase or decrease
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return (super.totalAssets() - _calculateLockedProfits()).safeAdd(netLoans + _calculateLockedLosses());
    }

    // Free liquidity available to withdraw or borrow
    // Locked profits are locked for every operation
    // We do not consider negative profits since they are not true liquidity
    function freeLiquidity() public view override returns (uint256) {
        return super.totalAssets() - _calculateLockedProfits();
    }

    // Assets include netLoans but they are not available for withdraw
    // Therefore we need to cap with the current free liquidity
    function maxWithdraw(address owner) public view override(ERC4626, IERC4626) returns (uint256) {
        return freeLiquidity().min(super.maxWithdraw(owner));
    }

    function depositWithPermit(uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256)
    {
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);

        return deposit(assets, receiver);
    }

    // Throws 'ERC20: transfer amount exceeds balance
    // IERC20(asset()).balanceOf(address(this)) < assets
    // Needs approvals if caller is not owner
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, IERC4626)
        returns (uint256)
    {
        // Due to ERC4626 collateralization constraint, we must enforce impossibility of zero balance
        // Therefore we need to revert if assets >= freeLiq rather than assets > freeLiq
        uint256 freeLiq = freeLiquidity();
        if (assets >= freeLiq) revert InsufficientLiquidity();
        uint256 shares = super.withdraw(assets, receiver, owner);

        emit Withdrawn(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    // Needs approvals if caller is not owner
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, IERC4626)
        returns (uint256)
    {
        uint256 freeLiq = freeLiquidity();
        uint256 assets = previewRedeem(shares);
        if (assets >= freeLiq) revert InsufficientLiquidity();
        super.redeem(shares, receiver, owner);

        emit Withdrawn(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    // mint and burn are used to manage boosting and seniority in loans

    // Minting during a loss is equivalent to declaring the receiver senior
    // Minting dilutes stakers (damping)
    // Use case: treasury, backing contract...
    // Invariant: maximumWithdraw(account) for account != receiver
    function directMint(uint256 shares, address receiver) external override onlyOwner returns (uint256) {
        // When minting, the receiver assets increase
        // Thus we produce negative profits and we need to lock them
        uint256 increasedAssets = convertToAssets(shares);
        _mint(receiver, shares);

        currentProfits = _calculateLockedProfits();
        currentLosses = _calculateLockedLosses() + increasedAssets;
        latestRepay = block.timestamp;

        emit DirectMint(receiver, shares, increasedAssets);

        return increasedAssets;
    }

    // Burning during a loss is equivalent to declaring the owner junior
    // Burning undilutes stakers (boosting)
    // Use case: insurance reserve...
    // Invariants: maximumWithdraw(account) for account != receiver
    function directBurn(uint256 shares, address owner) external override onlyOwner returns (uint256) {
        // Burning the entire supply would trigger an _initialConvertToShares at next deposit
        // Meaning that the first to deposit will get everything
        // To avoid overriding _initialConvertToShares, we make the following check
        if (shares >= totalSupply()) revert BurnThresholdExceeded();

        // When burning, the owner assets are distributed to others
        // Thus we need to lock them in order to avoid flashloan attacks
        uint256 distributedAssets = convertToAssets(shares);

        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);

        // Since this is onlyOwner we are not worried about reentrancy
        // So we can modify the state here
        currentProfits = _calculateLockedProfits() + distributedAssets;
        currentLosses = _calculateLockedLosses();
        latestRepay = block.timestamp;

        emit DirectBurn(owner, shares, distributedAssets);

        return distributedAssets;
    }

    // Owner is the only trusted borrower
    // Invariant: totalAssets()
    function borrow(uint256 assets, address receiver) external override onlyOwner returns (uint256, uint256) {
        uint256 freeLiq = freeLiquidity();
        // At the very worst case, the borrower repays nothing
        // In this case we need to avoid division by zero by putting >= rather than >
        if (assets >= freeLiq) revert InsufficientFreeLiquidity();
        // Net loans are in any moment less than IERC20(asset()).totalSupply()
        // Thus the next sum never overflows
        netLoans += assets;
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
        return currentProfits.safeMulDiv(feeUnlockTime.positiveSub(block.timestamp - latestRepay), feeUnlockTime);
    }

    // Starts from currentLosses and go linearly to 0
    // It is zero when block.timestamp-latestRepay > feeUnlockTime
    function _calculateLockedLosses() internal view returns (uint256) {
        return currentLosses.safeMulDiv(feeUnlockTime.positiveSub(block.timestamp - latestRepay), feeUnlockTime);
    }
}
