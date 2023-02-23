// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Base } from "./Base.script.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { Manager } from "../src/Manager.sol";

contract DeployManager is Base {
    Manager internal manager;

    function _run() internal override {
        manager = new Manager();
        assert(address(manager) != address(0));
    }
}
