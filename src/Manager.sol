// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Vault } from "./Vault.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IManager } from "./interfaces/IManager.sol";

contract Manager is IManager, Ownable {
    bytes32 public constant override salt = "ithil";
    mapping(address => address) public override vaults;
    mapping(address => bool) public services;

    modifier onlyServices() {
        if (!services[msg.sender]) revert Restricted_To_Whitelisted_Services();
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

    function addService(address service) external onlyOwner {
        services[service] = true;

        emit ServiceWasAdded(service);
    }

    function removeService(address service) external onlyOwner {
        assert(services[service]);
        delete services[service];

        emit ServiceWasRemoved(service);
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
        onlyServices
        returns (uint256, uint256)
    {
        return IVault(vaults[token]).borrow(amount, receiver);
    }

    /// @inheritdoc IManager
    function repay(address token, uint256 amount, uint256 debt, address repayer)
        external
        override
        exists(token)
        onlyServices
    {
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
