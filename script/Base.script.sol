// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Script } from "forge-std/Script.sol";

abstract contract Base is Script {
    uint256 internal deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        _run();

        vm.stopBroadcast();
    }

    function _run() internal virtual;
}
