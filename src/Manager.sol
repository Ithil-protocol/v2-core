// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ETHWrapper } from "./utils/ETHWrapper.sol";
import { Multicall } from "./utils/Multicall.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IManager } from "./interfaces/IManager.sol";
import { Vault } from "./Vault.sol";
import { GeneralMath } from "./libraries/GeneralMath.sol";

contract Manager is IManager, Ownable, ETHWrapper, Multicall {
    using GeneralMath for uint256;

    bytes32 public constant override salt = "ithil";
    mapping(address => address) public override vaults;
    // service => token => RiskParams
    mapping(address => mapping(address => RiskParams)) public riskParams;

    // solhint-disable-next-line no-empty-blocks
    constructor(address weth) ETHWrapper(weth) {}

    modifier supported(address token) {
        if (riskParams[msg.sender][token].cap == 0) revert Restricted_To_Whitelisted_Services();
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

    function setSpread(address service, address token, uint256 spread) external onlyOwner {
        riskParams[service][token].spread = spread;

        emit SpreadWasUpdated(service, token, spread);
    }

    function setCap(address service, address token, uint256 cap) external onlyOwner {
        riskParams[service][token].cap = cap;

        emit CapWasUpdated(service, token, cap);
    }

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external override onlyOwner {
        IVault(vaults[token]).setFeeUnlockTime(feeUnlockTime);
    }

    function sweep(address to, address token, address vault) external onlyOwner {
        IVault(vault).sweep(to, token);
    }

    /// @inheritdoc IManager
    function deposit(address token, uint256 amount, address receiver, address owner)
        external
        override
        supported(token)
        returns (uint256)
    {
        uint256 investmentCap = riskParams[msg.sender][token].cap;
        uint256 shares = IVault(vaults[token]).deposit(amount, receiver, owner);
        uint256 currentExposure = riskParams[msg.sender][token].exposure + shares;
        riskParams[msg.sender][token].exposure = currentExposure;
        uint256 investedPortion = GeneralMath.RESOLUTION.safeMulDiv(
            currentExposure,
            IVault(vaults[token]).totalSupply()
        );
        if (investedPortion > investmentCap) revert Invesment_Exceeded_Cap(investedPortion, investmentCap);
        return shares;
    }

    /// @inheritdoc IManager
    function withdraw(address token, uint256 amount, address receiver, address owner)
        external
        override
        supported(token)
        returns (uint256)
    {
        uint256 shares = IVault(vaults[token]).withdraw(amount, receiver, owner);
        riskParams[msg.sender][token].exposure = riskParams[msg.sender][token].exposure.positiveSub(shares);
        return shares;
    }

    /// @inheritdoc IManager
    function borrow(address token, uint256 amount, address receiver)
        external
        override
        supported(token)
        returns (uint256, uint256)
    {
        uint256 currentExposure = riskParams[msg.sender][token].exposure + amount;
        riskParams[msg.sender][token].exposure = currentExposure;
        uint256 investmentCap = riskParams[msg.sender][token].cap;
        (uint256 freeLiquidity, uint256 netLoans) = IVault(vaults[token]).borrow(amount, receiver);
        uint256 investedPortion = GeneralMath.RESOLUTION.safeMulDiv(
            currentExposure,
            freeLiquidity.safeAdd(netLoans - amount)
        );
        if (investedPortion > investmentCap) revert Invesment_Exceeded_Cap(investedPortion, investmentCap);
        return (freeLiquidity, netLoans);
    }

    /// @inheritdoc IManager
    function repay(address token, uint256 amount, uint256 debt, address repayer) external override supported(token) {
        riskParams[msg.sender][token].exposure = riskParams[msg.sender][token].exposure.positiveSub(debt);
        IVault(vaults[token]).repay(amount, debt, repayer);
    }

    /// @inheritdoc IManager
    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn)
        external
        override
        supported(token)
        returns (uint256)
    {
        uint256 amountIn = IVault(vaults[token]).directMint(shares, to);
        if (amountIn > maxAmountIn) revert Max_Amount_Exceeded();

        return amountIn;
    }

    /// @inheritdoc IManager
    function directBurn(address token, address from, uint256 shares, uint256 maxAmountIn)
        external
        override
        supported(token)
        returns (uint256)
    {
        uint256 amountIn = IVault(vaults[token]).directBurn(shares, from);
        if (amountIn > maxAmountIn) revert Max_Amount_Exceeded();

        return amountIn;
    }
}
