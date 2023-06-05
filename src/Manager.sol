// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IManager } from "./interfaces/IManager.sol";
import { GeneralMath } from "./libraries/GeneralMath.sol";
import { Vault } from "./Vault.sol";

contract Manager is IManager, Ownable {
    using GeneralMath for uint256;

    bytes32 public constant override salt = "ithil";
    mapping(address => address) public override vaults;
    // service => token => caps
    mapping(address => mapping(address => CapsAndExposures)) public override caps;
    mapping(address => uint256) public exposures;

    // solhint-disable-next-line no-empty-blocks
    constructor() {}

    modifier supported(address token) {
        if (caps[msg.sender][token].cap == 0) revert RestrictedToWhitelisted();
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

        return vault;
    }

    function setCap(address service, address token, uint256 cap) external override onlyOwner {
        caps[service][token].cap = cap;

        emit CapWasUpdated(service, token, cap);
    }

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external override onlyOwner {
        IVault(vaults[token]).setFeeUnlockTime(feeUnlockTime);
    }

    function sweep(address vaultToken, address spuriousToken, address to) external onlyOwner {
        IVault(vaults[vaultToken]).sweep(to, spuriousToken);
    }

    /// @inheritdoc IManager
    function borrow(address token, uint256 amount, uint256 loan, address receiver)
        external
        override
        supported(token)
        vaultExists(token)
        returns (uint256, uint256)
    {
        // Example with USDC: investmentCap = 2e17 (20%)
        // initial freeLiquidity = 1e13 (10 million USDC), initial netLoans = 3e12 (3 million USDC)
        // we borrow 100k more, then freeLiquidity becomes 9.9e12 and netLoans = 3.1e12
        // assume currentExposure = 1.1e12 (1.1 million USDC) coming also from last 100k
        // finally investedPortion = 1e18 * 1.1e12 / (9.9e12 + 3.1e12) = 85271317829457364 or about 8.53%
        uint256 investmentCap = caps[msg.sender][token].cap;
        caps[msg.sender][token].exposure += loan;
        (uint256 freeLiquidity, uint256 netLoans) = IVault(vaults[token]).borrow(amount, loan, receiver);
        uint256 investedPortion = GeneralMath.RESOLUTION.safeMulDiv(
            caps[msg.sender][token].exposure,
            freeLiquidity.safeAdd(netLoans)
        );
        if (investedPortion > investmentCap) revert InvestmentCapExceeded(investedPortion, investmentCap);
        return (freeLiquidity, netLoans);
    }

    /// @inheritdoc IManager
    function repay(address token, uint256 amount, uint256 debt, address repayer)
        external
        override
        supported(token)
        vaultExists(token)
    {
        caps[msg.sender][token].exposure = caps[msg.sender][token].exposure.positiveSub(debt);
        IVault(vaults[token]).repay(amount, debt, repayer);
    }
}
