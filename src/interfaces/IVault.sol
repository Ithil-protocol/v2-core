// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title    Interface of the Vault contract
/// @author   Ithil
interface IVault is IERC4626 {
    function borrow(uint256 assets, address receiver) external;
    function repay(uint256 assets, uint256 debt, address repayer) external;
        
    // Events
    event DegradationCoefficientWasChanged(uint256 degradationCoefficient);
    event Deposited(address indexed user, address indexed receiver, uint256 assets, uint256 shares);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Borrowed(address indexed receiver, uint256 assets);
    event Repaid(address indexed repayer, uint256 amount, uint256 debt);
    event DirectMint(address indexed receiver, uint256 shares, uint256 increasedAssets);
    event DirectBurn(address indexed receiver, uint256 shares, uint256 distributedAssets);

    // Errors
    error Insufficient_Liquidity(uint256 balance);
    error Insufficient_Free_Liquidity(uint256 freeLiquidity);
    error Supply_Burned();
    error Fee_Unlock_Out_Of_Range();
}
