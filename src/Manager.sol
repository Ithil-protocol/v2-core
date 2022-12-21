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

    // service => token => spreadAndCap (packed), if 0 then it is not supported
    mapping(address => mapping(address => uint256)) public spreadAndCaps;
    mapping(address => mapping(address => uint256)) public exposures;

    // solhint-disable-next-line no-empty-blocks
    constructor(address weth) ETHWrapper(weth) {}

    modifier supported(address token) {
        if (spreadAndCaps[msg.sender][token] == 0) revert Restricted_To_Whitelisted_Services();
        _;
    }

    modifier exists(address token) {
        if (vaults[token] == address(0)) revert Vault_Missing();
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

    function setSpreadAndCap(address service, address token, uint256 spread, uint256 cap) external onlyOwner {
        spreadAndCaps[service][token] = GeneralMath.packInUint(spread, cap);

        emit SpreadAndCapWasSet(service, token, spread, cap);
    }

    function removeTokenFromService(address service, address token) external onlyOwner {
        assert(spreadAndCaps[service][token] > 0);
        delete spreadAndCaps[service][token];

        emit TokenWasRemovedFromService(service, token);
    }

    function setFeeUnlockTime(address token, uint256 feeUnlockTime) external override exists(token) {
        IVault(vaults[token]).setFeeUnlockTime(feeUnlockTime);
    }

    function sweep(address to, address token, address vault) external onlyOwner {
        IVault(vault).sweep(to, token);
    }

    /// @inheritdoc IManager
    function borrow(address token, uint256 amount, address receiver)
        external
        override
        exists(token)
        supported(token)
        returns (uint256, uint256)
    {
        uint256 currentExposures = exposures[msg.sender][token].safeAdd(amount);
        exposures[msg.sender][token] = currentExposures;
        (, uint256 investmentCap) = spreadAndCaps[msg.sender][token].unpackUint();
        (uint256 freeLiquidity, uint256 netLoans) = IVault(vaults[token]).borrow(amount, receiver);
        uint256 investedPortion = GeneralMath.RESOLUTION.safeMulDiv(
            currentExposures,
            freeLiquidity.safeAdd(netLoans - amount)
        );
        if (investedPortion > investmentCap) revert Invesment_Exceeded_Cap(investedPortion, investmentCap);
        return (freeLiquidity, netLoans);
    }

    /// @inheritdoc IManager
    function repay(address token, uint256 amount, uint256 debt, address repayer)
        external
        override
        exists(token)
        supported(token)
    {
        exposures[msg.sender][token] = exposures[msg.sender][token].positiveSub(debt);
        IVault(vaults[token]).repay(amount, debt, repayer);
    }

    /// @inheritdoc IManager
    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn)
        external
        override
        exists(token)
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
        exists(token)
        returns (uint256)
    {
        uint256 amountIn = IVault(vaults[token]).directBurn(shares, from);
        if (amountIn > maxAmountIn) revert Max_Amount_Exceeded();

        return amountIn;
    }
}
