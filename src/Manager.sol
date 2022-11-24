// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Vault } from "./Vault.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IManager } from "./interfaces/IManager.sol";

contract Manager is IManager, Ownable {
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

        address vault = address(new Vault{ salt: keccak256(abi.encode(token)) }(IERC20Metadata(token)));
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

    /// @inheritdoc IManager
    function borrow(address token, uint256 amount) external override exists(token) onlyServices {
        IVault(vaults[token]).borrow(amount, msg.sender);
    }

    /// @inheritdoc IManager
    function repay(address token, uint256 amount, uint256 debt) external override exists(token) onlyServices {
        IVault(vaults[token]).repay(amount, debt, msg.sender);
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
