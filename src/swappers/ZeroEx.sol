// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IZeroExRouter } from "../interfaces/external/0x/IZeroExRouter.sol";
import { Swapper } from "./Swapper.sol";

contract ZeroEx is Swapper {
    using SafeERC20 for IERC20;

    IZeroExRouter public immutable router;

    constructor(address _router) {
        router = IZeroExRouter(_router);
    }

    function swap(address from, address to, uint256 amount, uint256 minOut, bytes calldata data) external override {
        if (IERC20(from).allowance(address(this), address(router)) == 0)
            IERC20(from).safeApprove(address(router), type(uint256).max);

        IZeroExRouter.Transformation[] memory transformations = abi.decode(data, (IZeroExRouter.Transformation[]));
        router.transformERC20(from, to, amount, minOut, transformations);

        IERC20 outToken = IERC20(to);
        uint256 obtained = outToken.balanceOf(address(this));
        if (obtained < minOut) revert TooMuchSlippage();

        outToken.safeTransfer(msg.sender, obtained);

        emit SwapWasExecuted(from, to, amount, obtained);
    }
}
