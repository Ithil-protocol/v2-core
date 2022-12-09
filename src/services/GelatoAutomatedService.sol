// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITaskTreasuryUpgradable } from "../interfaces/external/ITaskTreasuryUpgradable.sol";
import { IGelatoOps } from "../interfaces/external/IGelatoOps.sol";
import { Service } from "./Service.sol";

abstract contract GelatoAutomatedService is Service {
    address public immutable weth;
    IGelatoOps public immutable ops;
    ITaskTreasuryUpgradable public immutable gelatoTreasury;
    bytes32 public taskId;

    event NewGelatoTaskWasAdded(bytes32 indexed taskId);
    event GelatoTreasuryRefill(uint256 amount);
    event GelatoTaskWasRemoved(bytes32 indexed taskId);
    event ExecutedByGelato(uint256 gelatoFee);

    constructor(address _weth, address _ops) {
        weth = _weth;
        ops = IGelatoOps(_ops);
        gelatoTreasury = ops.taskTreasury();

        IERC20(weth).approve(address(gelatoTreasury), type(uint256).max);
    }

    function createTask() external onlyOwner {
        assert(taskId == bytes32(0)); // cannot create if already exitst

        bytes memory execData = abi.encodeCall(this.exec, ());
        IGelatoOps.ModuleData memory moduleData = IGelatoOps.ModuleData({
            modules: new IGelatoOps.Module[](1),
            args: new bytes[](1)
        });
        moduleData.modules[0] = IGelatoOps.Module.RESOLVER;
        moduleData.args[0] = abi.encode(address(this), abi.encodeCall(this.check, ()));

        taskId = ops.createTask(address(this), execData, moduleData, weth);

        emit NewGelatoTaskWasAdded(taskId);
    }

    function cancelTask() external virtual onlyGuardian {
        assert(taskId != bytes32(0)); // cannot cancel if not exitst

        ops.cancelTask(taskId);
        taskId = bytes32(0);

        emit GelatoTaskWasRemoved(taskId);
    }

    // TODO maybe this should be external
    function payKeeper(uint256 amount) internal {
        gelatoTreasury.depositFunds(address(this), weth, amount);

        emit GelatoTreasuryRefill(amount);
    }

    /** 
    * @dev To be implemented
    * Example:
            bool canExec = true;
            bytes memory execPayload = abi.encodeWithSelector(
                this.execute.selector
            );

            emit ExecutedByGelato(fees);

            return (canExec, execPayload);
    */
    function check() external view virtual returns (bool, bytes memory) {}

    /// @dev To be implemented
    function exec() external virtual {}
}
