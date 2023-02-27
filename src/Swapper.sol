// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IZeroExRouter } from "./interfaces/external/0x/IZeroExRouter.sol";
import { PriceConverter } from "./libraries/external/ChainLink/PriceConverter.sol";

contract Swapper is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    IZeroExRouter public immutable router;
    mapping(address => address) public oracles; // token -> feed

    event PriceFeedWasUpdated(address indexed token, address indexed feed);
    event SwapWasExecuted(address indexed from, address indexed to, uint256 sold, uint256 obtained);
    error TokenNotSupported();
    error TooMuchSlippage();

    constructor(address _router) {
        router = IZeroExRouter(_router);
    }

    function addPriceFeed(address token, address feed) external onlyOwner {
        oracles[token] = feed;

        emit PriceFeedWasUpdated(token, feed);
    }

    function swap(address from, address to, uint256 amount, uint256 slippage, bytes calldata data) external {
        if (oracles[from] == address(0) || oracles[to] == address(0)) revert TokenNotSupported();

        IERC20 inToken = IERC20(from);
        ERC20 outToken = ERC20(to);
        inToken.safeTransferFrom(msg.sender, address(this), amount);
        inToken.approve(address(router), amount);

        uint256 minOut = uint256(_getPrice(from, to, outToken.decimals())) * amount - slippage;

        IZeroExRouter.Transformation[] memory transformations = abi.decode(data, (IZeroExRouter.Transformation[]));
        router.transformERC20(from, to, amount, minOut, transformations);

        uint256 obtained = outToken.balanceOf(address(this));
        if (obtained < minOut) revert TooMuchSlippage();

        outToken.safeTransfer(msg.sender, obtained);

        emit SwapWasExecuted(from, to, amount, obtained);
    }

    function _getPrice(address from, address to, uint8 decimals) internal view returns (int256) {
        return PriceConverter.getDerivedPrice(oracles[from], oracles[to], decimals);
    }
}
