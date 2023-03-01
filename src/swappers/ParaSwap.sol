// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAugustusSwapper } from "../interfaces/external/paraswap/IAugustusSwapper.sol";
import { BaseSwapper } from "./BaseSwapper.sol";

contract ParaSwap is BaseSwapper {
    using SafeERC20 for IERC20;

    IAugustusSwapper public immutable router;
    address public immutable proxy;

    constructor(address _router, address _proxy) {
        router = IAugustusSwapper(_router);
        proxy = _proxy;
    }

    function swap(address from, address to, uint256 amount, uint256 minOut, bytes calldata data) external override {
        IERC20 inToken = IERC20(from);
        inToken.safeTransferFrom(msg.sender, address(this), amount);
        inToken.approve(proxy, amount);

        IAugustusSwapper.SimpleData memory swapData = abi.decode(data, (IAugustusSwapper.SimpleData));
        router.simpleSwap(swapData);

        IERC20 outToken = IERC20(to);
        uint256 obtained = outToken.balanceOf(address(this));
        if (obtained < minOut) revert TooMuchSlippage();

        outToken.safeTransfer(msg.sender, obtained);

        emit SwapWasExecuted(from, to, amount, obtained);
    }
}
