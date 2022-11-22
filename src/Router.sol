// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ETHWrapper } from "./ETHWrapper.sol";
import { Multicall } from "./Multicall.sol";
import { Vault } from "./Vault.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IRouter } from "./interfaces/IRouter.sol";

contract Router is IRouter, Multicall, ETHWrapper, Ownable {
    bytes32 public constant SALT = "ithil-router";
    mapping(address => address) public vaults; // TODO should we use static routing instead?

    constructor(address _weth) ETHWrapper(_weth) {}

    function deploy(address token) external onlyOwner {
        vaults[token] = Create2.deploy(0, SALT, type(Vault).creationCode);
    }

    /// @inheritdoc IRouter
    function mint(IERC4626 vault, address to, uint256 shares, uint256 maxAmountIn)
        external
        override
        returns (uint256 amountIn)
    {
        if ((amountIn = vault.mint(shares, to)) > maxAmountIn) {
            revert MaxAmountError();
        }
    }

    /// @inheritdoc IRouter
    function deposit(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        override
        returns (uint256 sharesOut)
    {
        if ((sharesOut = vault.deposit(amount, to)) < minSharesOut) {
            revert MinSharesError();
        }
    }

    /// @inheritdoc IRouter
    function withdraw(IERC4626 vault, address to, uint256 amount, uint256 maxSharesOut)
        external
        override
        returns (uint256 sharesOut)
    {
        if ((sharesOut = vault.withdraw(amount, to, msg.sender)) > maxSharesOut) {
            revert MaxSharesError();
        }
    }

    /// @inheritdoc IRouter
    function redeem(IERC4626 vault, address to, uint256 shares, uint256 minAmountOut)
        external
        override
        returns (uint256 amountOut)
    {
        if ((amountOut = vault.redeem(shares, to, msg.sender)) < minAmountOut) {
            revert MinAmountError();
        }
    }
}
