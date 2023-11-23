// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { PriceConverter } from "./libraries/external/ChainLink/PriceConverter.sol";

contract Oracle is IOracle, Ownable {
    mapping(address => address) public oracles; // token -> feed

    event PriceFeedWasUpdated(address indexed token, address indexed feed);

    error TokenNotSupported();

    function setPriceFeed(address token, address feed) external onlyOwner {
        oracles[token] = feed;

        emit PriceFeedWasUpdated(token, feed);
    }

    function getPrice(address from, address to, uint8 resolution) external view override returns (uint256) {
        if (oracles[from] == address(0) || oracles[to] == address(0)) revert TokenNotSupported();

        return uint256(PriceConverter.getDerivedPrice(oracles[from], oracles[to], resolution));
    }
}
