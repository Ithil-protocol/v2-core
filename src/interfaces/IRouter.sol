// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

/// @title    Interface of the Router contract
/// @author   Ithil
/// @notice   A canonical router between ERC4626 Vaults https://eips.ethereum.org/EIPS/eip-4626
interface IRouter {
    event ServiceWasAdded(address indexed service);
    event ServiceWasRemoved(address indexed service);

    /// @notice thrown when amount of assets received is below the min set by caller
    error Below_Min_Amount();

    /// @notice thrown when amount of shares received is below the min set by caller
    error Below_Min_Shares();

    /// @notice thrown when amount of assets received is above the max set by caller
    error Max_Amount_Exceeded();

    /// @notice thrown when amount of shares received is above the max set by caller
    error Max_Shares_Exceeded();

    error Vault_Missing();
    error Restricted_To_Whitelisted_Services();

    /** 
     @notice mint `shares` from an ERC4626 vault.
     @param token The token vault to mint shares from.
     @param to The destination of ownership shares.
     @param shares The amount of shares to mint from `vault`.
     @param maxAmountIn The max amount of assets used to mint.
     @return amountIn the amount of assets used to mint by `to`.
     @dev throws MaxAmountError   
    */
    function mint(address token, address to, uint256 shares, uint256 maxAmountIn) external returns (uint256 amountIn);

    /** 
     @notice deposit `amount` to an ERC4626 vault.
     @param token The token vault to deposit assets to.
     @param to The destination of ownership shares.
     @param amount The amount of assets to deposit to `vault`.
     @param minSharesOut The min amount of `vault` shares received by `to`.
     @return sharesOut the amount of shares received by `to`.
     @dev throws MinSharesError   
    */
    function deposit(address token, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut);

    /** 
     @notice withdraw `amount` from an ERC4626 vault.
     @param token The token vault to withdraw assets from.
     @param to The destination of assets.
     @param amount The amount of assets to withdraw from vault.
     @param minSharesOut The min amount of shares received by `to`.
     @return sharesOut the amount of shares received by `to`.
     @dev throws MaxSharesError   
    */
    function withdraw(address token, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut);

    /** 
     @notice redeem `shares` shares from an ERC4626 vault.
     @param token The token vault to redeem shares from.
     @param to The destination of assets.
     @param shares The amount of shares to redeem from vault.
     @param minAmountOut The min amount of assets received by `to`.
     @return amountOut the amount of assets received by `to`.
     @dev throws MinAmountError   
    */
    function redeem(address token, address to, uint256 shares, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    function get(address token) external view returns (address);

    function directMint(address token, address to, uint256 shares, uint256 maxAmountIn) external returns (uint256);

    function directBurn(address token, address from, uint256 shares, uint256 maxAmountIn) external returns (uint256);

    function borrow(address token, uint256 amount) external;

    function repay(address token, uint256 amount, uint256 debt) external;
}
