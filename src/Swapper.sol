// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapper } from "./interfaces/ISwapper.sol";
import { IUniswapV2Router } from "./interfaces/external/sushi/IUniswapV2Router.sol";
import { BalancerHelper } from "./libraries/BalancerHelper.sol";
import { CurveHelper } from "./libraries/CurveHelper.sol";

contract Swapper is ISwapper, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => SwapData)) public paths;
    mapping(Dex => address) public dexes;

    function changeDexRouter(Dex dex, address router) external onlyOwner {
        dexes[dex] = router;
    }

    function changeSwapPath(address from, address to, SwapData memory data) external onlyOwner {
        paths[from][to] = data;
    }

    function swap(address from, address to, uint256 amountIn, uint256 minOut) external override {
        SwapData memory pool = paths[from][to];
        address router = dexes[pool.dex];

        if (pool.dex == Dex.NONE || router == address(0)) revert SwapNotPossible();

        if (IERC20(from).allowance(address(this), address(router)) < amountIn)
            IERC20(from).approve(address(router), type(uint256).max);

        if (pool.dex == Dex.BALANCER) {
            bytes32 poolID = abi.decode(pool.data, (bytes32));
            BalancerHelper.swap(router, poolID, from, to, amountIn, minOut, block.timestamp);
        } else if (pool.dex == Dex.CURVE) {
            int128[2] memory indexes = abi.decode(pool.data, (int128[2]));
            CurveHelper.swap(router, indexes[0], indexes[1], amountIn, minOut);
        } else if (pool.dex == Dex.GMX) {
            // TODO add
            // IGmxRouter(router).swap(address[] _path, uint256 _amountIn, uint256 _minOut, address _receiver)
        } else {
            // Sushi and UniV2 share the same codebase
            IUniswapV2Router(router).swapExactTokensForTokens(amountIn, minOut, pool.path, msg.sender, block.timestamp);
        }
    }
}
