// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFactory } from "../../src/interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../src/interfaces/external/wizardex/IPool.sol";

contract MockDex is IFactory, IPool {
    using SafeERC20 for IERC20;

    function simuateOrderFulfillment(address token, uint256 amount, address target) external {
        IERC20(token).safeTransfer(target, amount);
    }

    function pools(address underlying, address accounting, uint16 tickSpacing) external view returns (address) {
        return address(this);
    }

    function tickSupported(uint16 tick) external view returns (bool) {
        return true;
    }

    function createPool(
        address underlying,
        address accounting,
        uint16 tickSpacing
    ) external returns (address, address) {
        revert("not implemented");
    }

    function createOrder(
        uint256 amount,
        uint256 price,
        address recipient,
        uint256 deadline
    ) external payable override {}

    function cancelOrder(uint256 index, uint256 price) external {}

    function fulfillOrder(
        uint256 amount,
        address receiver,
        uint256 minReceived,
        uint256 maxPaid,
        uint256 deadline
    ) external returns (uint256, uint256) {}
}
