// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Script } from "forge-std/Script.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { Manager } from "../../src/Manager.sol";

contract LendingPageRequirements is Script {
    Manager internal manager;
    uint256 internal deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address internal token0 = vm.envAddress("TOKEN0");
    address internal token1 = vm.envAddress("TOKEN1");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        manager = new Manager();
        assert(address(manager) != address(0));

        manager.create(token0);
        manager.create(token1);

        IVault vault0 = IVault(manager.vaults(token0));
        assert(vault0.asset() == token0);

        IVault vault1 = IVault(manager.vaults(token1));
        assert(vault1.asset() == token1);

        vm.stopBroadcast();
    }
}
