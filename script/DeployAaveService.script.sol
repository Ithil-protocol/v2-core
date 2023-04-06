// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Base } from "./Base.script.sol";
import { AaveService } from "../src/services/debit/AaveService.sol";

contract DeployAaveService is Base {
    address internal manager = vm.envAddress("MANAGER");
    address internal aave = vm.envAddress("AAVE");

    AaveService internal service;

    function _run() internal override {
        service = new AaveService(manager, aave, 2592000); // 1 month deadline
        assert(address(manager) != address(0));
        assert(address(service) != address(0));
        assert(keccak256(abi.encodePacked(service.name())) == keccak256(abi.encodePacked("AaveService")));
    }
}
