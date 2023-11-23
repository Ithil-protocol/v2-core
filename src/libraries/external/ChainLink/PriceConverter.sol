// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import { AggregatorV3Interface } from "../../../interfaces/external/chainlink/AggregatorV3Interface.sol";

library PriceConverter {
    error StaleOracleData();

    function getDerivedPrice(address _base, address _quote, uint8 _decimals) public view returns (int256) {
        int256 decimals = int256(10 ** uint256(_decimals));
        (
            ,
            /*uint80 roundId*/
            int256 basePrice,
            ,
            /*uint256 startedAt*/
            uint256 updatedAt /*uint80 answeredInRound*/,

        ) = AggregatorV3Interface(_base).latestRoundData();
        if (updatedAt < block.timestamp - 1 days) revert StaleOracleData();

        uint8 baseDecimals = AggregatorV3Interface(_base).decimals();
        basePrice = scalePrice(basePrice, baseDecimals, _decimals);

        (
            ,
            /*uint80 roundId*/
            int256 quotePrice,
            ,
            /*uint256 startedAt*/
            uint256 timestamp /*uint80 answeredInRound*/,

        ) = AggregatorV3Interface(_quote).latestRoundData();
        if (timestamp < block.timestamp - 1 days) revert StaleOracleData();

        uint8 quoteDecimals = AggregatorV3Interface(_quote).decimals();
        quotePrice = scalePrice(quotePrice, quoteDecimals, _decimals);

        return (basePrice * decimals) / quotePrice;
    }

    function scalePrice(int256 _price, uint8 _priceDecimals, uint8 _decimals) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10 ** uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10 ** uint256(_priceDecimals - _decimals));
        }
        return _price;
    }
}
