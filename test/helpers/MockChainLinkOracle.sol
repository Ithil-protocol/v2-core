// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { AggregatorV3Interface } from "../../src/interfaces/external/chainlink/AggregatorV3Interface.sol";

contract MockChainLinkOracle is AggregatorV3Interface {
    uint8 internal immutable dec;
    int256 internal price;

    constructor(uint8 _dec) {
        dec = _dec;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function decimals() external view override returns (uint8) {
        return dec;
    }

    function description() external view override returns (string memory) {
        return "Mock Chainlink Oracle";
    }

    function version() external view override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, price, 0, block.timestamp, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, price, 0, block.timestamp, 0);
    }
}
