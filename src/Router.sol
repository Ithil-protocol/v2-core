// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ETHWrapper } from "./ETHWrapper.sol";
import { Multicall } from "./Multicall.sol";
import { IRouter } from "./interfaces/IRouter.sol";

contract Router is IRouter, Multicall, ETHWrapper {
    using SafeERC20 for IERC20;

    // solhint-disable-next-line no-empty-blocks
    constructor(address weth) ETHWrapper(weth) {}

    /// @inheritdoc IRouter
    function selfPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function approve(IERC20 token, address to, uint256 amount) external override {
        token.safeApprove(to, amount);
    }

    /// @inheritdoc IRouter
    function deposit(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        override
        returns (uint256)
    {
        IERC20 token = IERC20(vault.asset());
        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 sharesOut = vault.deposit(amount, to);
        if (sharesOut < minSharesOut) revert Below_Min_Shares();

        return sharesOut;
    }

    /// @inheritdoc IRouter
    function withdraw(IERC4626 vault, address to, uint256 amount, uint256 maxSharesOut)
        external
        override
        returns (uint256)
    {
        uint256 sharesOut = vault.withdraw(amount, to, msg.sender);
        if (sharesOut > maxSharesOut) revert Max_Shares_Exceeded();

        return sharesOut;
    }

    /// @inheritdoc IRouter
    function redeem(IERC4626 vault, address to, uint256 shares, uint256 minAmountOut)
        external
        override
        returns (uint256)
    {
        uint256 amountOut = vault.redeem(shares, to, msg.sender);
        if (amountOut < minAmountOut) revert Below_Min_Amount();

        return amountOut;
    }
}
