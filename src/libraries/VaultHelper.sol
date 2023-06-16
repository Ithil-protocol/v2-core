// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IManager } from "../interfaces/IManager.sol";
import { IVault } from "../interfaces/IVault.sol";
import { RESOLUTION } from "../Constants.sol";

library VaultHelper {
    /// @dev gets the vault with the highest free liquidity
    function getBestVault(address[] calldata tokens, IManager manager) external view returns (address, address) {
        uint256 lowestRatio = type(uint256).max;
        address bestToken;
        address bestVault;
        for (uint8 i = 0; i < tokens.length; i++) {
            IVault vault = IVault(manager.vaults(tokens[i]));
            uint256 totalAssets = vault.totalAssets(); // gas savings
            uint256 freeLiquidity = vault.freeLiquidity(); // gas savings
            if (totalAssets == 0) continue;
            if ((RESOLUTION * freeLiquidity) / totalAssets < lowestRatio) {
                lowestRatio = (RESOLUTION * freeLiquidity) / totalAssets;
                bestToken = tokens[i];
                bestVault = address(vault);
            }
        }

        // It can return address(0) to both values in case all tokens vaults are empty (totalAssets == 0)
        return (bestToken, bestVault);
    }
}
