// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IManager } from "./interfaces/IManager.sol";
import { Vault } from "./Vault.sol";
import { RESOLUTION } from "./Constants.sol";

contract Manager is IManager, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant override salt = "ithil";
    mapping(address => address) public override vaults;
    mapping(address => mapping(address => CapsAndExposures)) public override caps;

    modifier supported(address token) {
        if (caps[msg.sender][token].percentageCap == 0) revert RestrictedToWhitelisted();
        _;
    }

    modifier vaultExists(address token) {
        if (vaults[token] == address(0)) revert VaultMissing();
        _;
    }

    function create(address token) external onlyOwner returns (address) {
        assert(vaults[token] == address(0));

        address vault = Create2.deploy(
            0,
            salt,
            abi.encodePacked(type(Vault).creationCode, abi.encode(IERC20Metadata(token)))
        );
        vaults[token] = vault;
        // deposit 1 token unit to avoid the typical ERC4626 issue
        // by placing the resulting iToken in the manager, it becomes unredeemable
        // therefore, the Vault is guaranteed to always stay in a healthy status
        IERC20 tkn = IERC20(token);
        tkn.safeTransferFrom(msg.sender, address(this), 1);
        tkn.approve(vault, 1);
        IVault(vault).deposit(1, address(this));

        return vault;
    }

    function setCap(
        address service,
        address token,
        uint256 percentageCap,
        uint256 absoluteCap
    ) external override onlyOwner {
        caps[service][token].percentageCap = percentageCap;
        caps[service][token].absoluteCap = absoluteCap;

        emit CapWasUpdated(service, token, percentageCap, absoluteCap);
    }

    function setFeeUnlockTime(address vaultToken, uint256 feeUnlockTime) external override onlyOwner {
        assert(vaults[vaultToken] != address(0));

        IVault(vaults[vaultToken]).setFeeUnlockTime(feeUnlockTime);
    }

    function sweep(address vaultToken, address spuriousToken, address to) external onlyOwner {
        assert(vaults[vaultToken] != address(0));

        IVault(vaults[vaultToken]).sweep(to, spuriousToken);
    }

    function toggleVaultLock(address vaultToken) external onlyOwner {
        assert(vaults[vaultToken] != address(0));

        IVault(vaults[vaultToken]).toggleLock();
    }

    /// @inheritdoc IManager
    function borrow(
        address token,
        uint256 amount,
        uint256 loan,
        address receiver
    ) external override supported(token) vaultExists(token) returns (uint256, uint256) {
        // Example with USDC: investmentCap = 2e17 (20%)
        // initial freeLiquidity = 1e13 (10 million USDC), initial netLoans = 3e12 (3 million USDC)
        // we borrow 100k more, then freeLiquidity becomes 9.9e12 and netLoans = 3.1e12
        // assume currentExposure = 1.1e12 (1.1 million USDC) coming also from last 100k
        // finally investedPortion = 1e18 * 1.1e12 / (9.9e12 + 3.1e12) = 85271317829457364 or about 8.53%
        uint256 exposure = caps[msg.sender][token].exposure;
        if (exposure + loan > caps[msg.sender][token].absoluteCap) revert AbsoluteCapExceeded(exposure);
        caps[msg.sender][token].exposure += loan;
        (uint256 netLoans, uint256 freeLiquidity) = IVault(vaults[token]).getLoansAndLiquidity();
        // therefore, the quantity freeLiquidity + netLoans - loan is invariant during the borrow
        // notice that since amount >= loan in general, we cannot make (freeLiquidity - amount)
        // otherwise credit services could be unclosable when experiencing a loss at high liquidity pressure
        uint256 investedPortion = RESOLUTION.mulDiv(exposure + loan, freeLiquidity + netLoans);
        if (investedPortion > caps[msg.sender][token].percentageCap) revert InvestmentCapExceeded(investedPortion);

        // at this point to prevent reentrancy
        IVault(vaults[token]).borrow(amount, loan, receiver);
        return (freeLiquidity, netLoans + loan);
    }

    /// @inheritdoc IManager
    function repay(
        address token,
        uint256 amount,
        uint256 debt,
        address repayer
    ) external override supported(token) vaultExists(token) {
        uint256 exposure = caps[msg.sender][token].exposure;
        caps[msg.sender][token].exposure = exposure < debt ? 0 : exposure - debt;
        IVault(vaults[token]).repay(amount, debt, repayer);
    }
}
