// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Base } from "./Base.script.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { IManager } from "../src/interfaces/IManager.sol";

contract CreateVault is Base {
    address internal manager = vm.envAddress("MANAGER");
    address internal token = vm.envAddress("TOKEN");

    function _run() internal override {
        IManager(manager).create(token);
        IVault vault = IVault(IManager(manager).vaults(token));
        assert(vault.asset() == token);
    }
}
