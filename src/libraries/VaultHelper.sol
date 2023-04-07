// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IManager } from "../interfaces/IManager.sol";
import { IVault } from "../interfaces/IVault.sol";

library VaultHelper {
    /// @dev gets the vault with the highest free liquidity
    function getBestVault(address[] calldata tokens, IManager manager) external view returns (address, address) {
        uint256 freeLiquidity = 0;
        address bestToken = tokens[0];
        address bestVault;
        for (uint8 i = 0; i < tokens.length; i++) {
            IVault vault = IVault(manager.vaults(tokens[i]));
            if (vault.freeLiquidity() > freeLiquidity) {
                freeLiquidity = vault.freeLiquidity();
                bestToken = tokens[i];
                bestVault = address(vault);
            }
        }

        return (bestToken, bestVault);
    }
}
