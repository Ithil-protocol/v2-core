// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@chainlink/contracts/src/v0.8/Denominations.sol";

contract UsesChainlink is Ownable {
    FeedRegistryInterface public immutable registry;
    uint256 public maxDeviation;

    event MaxDeviationWasUpdated(uint256 newDeviation);

    constructor(address _registry, uint256 _maxDeviation) {
        assert(_maxDeviation > 0);
        assert(_registry != address(0));

        registry = FeedRegistryInterface(_registry);
        maxDeviation = _maxDeviation;
    }

    function setMaxDeviation(uint256 newDeviation) external onlyOwner {
        assert(maxDeviation > 0);
        maxDeviation = newDeviation;

        emit MaxDeviationWasUpdated(newDeviation);
    }

    function getPrice(address base, address quote) public view returns (int256) {
        (
            /*uint80 roundID*/,
            int256 price,
            /*uint256 startedAt*/,
            uint256 timestamp,
            /*uint80 answeredInRound*/
        ) = registry.latestRoundData(base, quote);

        //if(block-timestamp - timestamp > timestamp)

        return price;
    }
}
