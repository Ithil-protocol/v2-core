// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC4626, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title    Interface of the Router contract
/// @author   Ithil
/// @notice   A canonical router between ERC4626 Vaults https://eips.ethereum.org/EIPS/eip-4626
interface IRouter {
    /// @notice thrown when amount of assets received is below the min set by caller
    error Below_Min_Amount();

    /// @notice thrown when amount of shares received is below the min set by caller
    error Below_Min_Shares();

    /// @notice thrown when amount of shares received is above the max set by caller
    error Max_Shares_Exceeded();

    function selfPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function approve(IERC20 token, address to, uint256 amount) external;

    /** 
     @notice deposit `amount` to an ERC4626 vault.
     @param vault The vault to deposit assets to.
     @param to The destination of ownership shares.
     @param amount The amount of assets to deposit to `vault`.
     @param minSharesOut The min amount of `vault` shares received by `to`.
     @return sharesOut the amount of shares received by `to`.
     @dev throws MinSharesError   
    */
    function deposit(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut);

    /** 
     @notice withdraw `amount` from an ERC4626 vault.
     @param vault The vault to withdraw assets from.
     @param to The destination of assets.
     @param amount The amount of assets to withdraw from vault.
     @param minSharesOut The min amount of shares received by `to`.
     @return sharesOut the amount of shares received by `to`.
     @dev throws MaxSharesError   
    */
    function withdraw(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut);

    /** 
     @notice redeem `shares` shares from an ERC4626 vault.
     @param vault The vault to redeem shares from.
     @param to The destination of assets.
     @param shares The amount of shares to redeem from vault.
     @param minAmountOut The min amount of assets received by `to`.
     @return amountOut the amount of assets received by `to`.
     @dev throws MinAmountError   
    */
    function redeem(IERC4626 vault, address to, uint256 shares, uint256 minAmountOut)
        external
        returns (uint256 amountOut);
}
