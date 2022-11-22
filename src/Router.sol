// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ETHWrapper } from "./ETHWrapper.sol";
import { Multicall } from "./Multicall.sol";
import { Vault } from "./Vault.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IRouter } from "./interfaces/IRouter.sol";

contract Router is IRouter, Multicall, ETHWrapper, Ownable {
    mapping(address => address) public vaults; // TODO should we use static routing instead?
    mapping(address => bool) public services;

    constructor(address weth) ETHWrapper(weth) {}

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
            keccak256(abi.encode(token)),
            abi.encode(type(Vault).creationCode, IERC20Metadata(token))
        );
        vaults[token] = vault;

        IERC20(token).approve(vault, type(uint256).max); // TODO do we need it?

        return vault;
    }

    function get(address token) external view override returns (address) {
        return Create2.computeAddress(
            keccak256(abi.encode(token)),
            keccak256(abi.encode(type(Vault).creationCode, IERC20Metadata(token)))
        );
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

    /// @inheritdoc IRouter
    function borrow(address token, uint256 amount) external override exists(token) onlyServices {
        assert(vaults[token] != address(0));

        IVault(vaults[token]).borrow(amount, msg.sender);
    }

    /// @inheritdoc IRouter
    function repay(address token, uint256 amount, uint256 debt) external override exists(token) onlyServices {
        IVault(vaults[token]).repay(amount, debt, msg.sender);
    }

    /// @inheritdoc IRouter
    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn)
        external
        override
        exists(token)
        returns (uint256 amountIn)
    {
        if ((amountIn = IVault(vaults[token]).directMint(shares, to)) > maxAmountIn) {
            revert Max_Amount_Exceeded();
        }
    }

    /// @inheritdoc IRouter
    function directBurn(address token, address from, uint256 shares, uint256 maxAmountIn)
        external
        override
        exists(token)
        returns (uint256 amountIn)
    {
        if ((amountIn = IVault(vaults[token]).directBurn(shares, from)) > maxAmountIn) {
            revert Max_Amount_Exceeded();
        }
    }

    ////////////////// Standard ERC4626 Interfaces //////////////////

    /// @inheritdoc IRouter
    function mint(address token, address to, uint256 shares, uint256 maxAmountIn)
        external
        override
        exists(token)
        returns (uint256 amountIn)
    {
        if ((amountIn = IVault(vaults[token]).mint(shares, to)) > maxAmountIn) {
            revert Max_Amount_Exceeded();
        }
    }

    /// @inheritdoc IRouter
    function deposit(address token, address to, uint256 amount, uint256 minSharesOut)
        external
        override
        exists(token)
        returns (uint256 sharesOut)
    {
        if ((sharesOut = IVault(vaults[token]).deposit(amount, to)) < minSharesOut) {
            revert Below_Min_Shares();
        }
    }

    /// @inheritdoc IRouter
    function withdraw(address token, address to, uint256 amount, uint256 maxSharesOut)
        external
        override
        exists(token)
        returns (uint256 sharesOut)
    {
        if ((sharesOut = IVault(vaults[token]).withdraw(amount, to, msg.sender)) > maxSharesOut) {
            revert Max_Shares_Exceeded();
        }
    }

    /// @inheritdoc IRouter
    function redeem(address token, address to, uint256 shares, uint256 minAmountOut)
        external
        override
        exists(token)
        returns (uint256 amountOut)
    {
        if ((amountOut = IVault(vaults[token]).redeem(shares, to, msg.sender)) < minAmountOut) {
            revert Below_Min_Amount();
        }
    }
}
