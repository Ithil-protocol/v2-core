// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { ITaskTreasuryUpgradable } from "../interfaces/external/ITaskTreasuryUpgradable.sol";
import { IGelatoOps } from "../interfaces/external/IGelatoOps.sol";
import { Service } from "./Service.sol";

abstract contract AutomatedService is Service {
    IGelatoOps public immutable ops;
    ITaskTreasuryUpgradable public immutable gelatoTreasury;
    address public immutable feeToken;
    bytes32 public immutable taskId;

    event ExecutedByGelato(uint256 gelatoFee);

    constructor(address _ops, address _feeToken) {
        ops = IGelatoOps(_ops);
        gelatoTreasury = ops.taskTreasury();
        feeToken = _feeToken;
        taskId = _createTask();
    }

    function _createTask() internal returns (bytes32) {
        bytes memory execData = abi.encodeCall(this.exec, ());
        IGelatoOps.ModuleData memory moduleData = IGelatoOps.ModuleData({
            modules: new IGelatoOps.Module[](1),
            args: new bytes[](1)
        });
        moduleData.modules[0] = IGelatoOps.Module.RESOLVER;
        moduleData.args[0] = abi.encode(address(this), abi.encodeCall(this.check, ()));

        return ops.createTask(address(this), execData, moduleData, feeToken);
    }

    function cancelTask() external virtual onlyGuardian {
        // TODO do we want to have a way to re-enable the task?
        ops.cancelTask(taskId);
    }

    function payKeeper(uint256 fee) internal {
        gelatoTreasury.depositFunds(address(this), feeToken, fee);
    }

    function check() external view virtual returns (bool, bytes memory) {
        // Example usage
        /*
            bool canExec = true;
            bytes memory execPayload = abi.encodeWithSelector(
                this.execute.selector
            );

            return (canExec, execPayload);
        */
    }

    function exec() external virtual {
        // Example usage
        /*
            assert(!locked);
            ...execution logic...
        */
    }
}
