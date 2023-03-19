// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Base } from "./Base.script.sol";
import { IManager } from "../src/interfaces/IManager.sol";

contract SetCap is Base {
    address internal manager = vm.envAddress("MANAGER");
    address internal service = vm.envAddress("SERVICE");
    address internal token = vm.envAddress("TOKEN");
    uint256 internal cap = vm.envUint("CAP");

    function _run() internal override {
        assert(manager != address(0));
        assert(service != address(0));
        assert(token != address(0));

        IManager(manager).setCap(service, token, cap);
    }
}
