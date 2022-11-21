// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { Script } from "forge-std/Script.sol";
import { Vault } from "../src/Vault.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract VaultScript is Script {
    Vault internal vault;

    function run() public {
        vm.startBroadcast();
        //vault = new Vault(...);
        vm.stopBroadcast();
    }
}
