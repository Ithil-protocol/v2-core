// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IZeroExRouter } from "./interfaces/external/0x/IZeroExRouter.sol";
import { UsesChainlink } from "./utils/UsesChainlink.sol";
import { console2 } from "forge-std/console2.sol";

contract Swapper {
    using SafeERC20 for IERC20;

    IZeroExRouter public immutable router;

    event SwapWasExecuted(address indexed from, address indexed to, uint256 sold, uint256 obtained);
    error TooMuchSlippage();

    constructor(address _router, address registry, uint256 maxTimeDeviation) {
        // UsesChainlink(registry, maxTimeDeviation) {
        router = IZeroExRouter(_router);
    }

    function swap(address from, address to, uint256 amount, uint256 slippage, bytes calldata data) external {
        IERC20 inToken = IERC20(from);
        inToken.safeTransferFrom(msg.sender, address(this), amount);
        inToken.approve(address(router), amount);

        uint256 minOut = (uint256(getPrice(from, to)) * (100 - slippage)) / 100;

        IZeroExRouter.Transformation[] memory transformations = abi.decode(data, (IZeroExRouter.Transformation[]));
        router.transformERC20(from, to, amount, minOut, transformations);

        IERC20 outToken = IERC20(to);
        uint256 obtained = outToken.balanceOf(address(this));
        if (obtained < minOut) revert TooMuchSlippage();

        outToken.safeTransfer(msg.sender, obtained);

        emit SwapWasExecuted(from, to, amount, obtained);
    }

    function getPrice(address from, address to) internal view returns (int256) {
        return 1;
    }
}
