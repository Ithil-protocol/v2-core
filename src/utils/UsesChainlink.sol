// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IChainlinkFeedRegistry } from "../interfaces/external/chainlink/IChainlinkFeedRegistry.sol";

contract UsesChainlink is Ownable {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant USD = address(840);
    address public constant EUR = address(978);
    IChainlinkFeedRegistry public immutable registry;
    uint256 public maxTimeDeviation;

    event MaxTimeDeviationValueWasUpdated(uint256 newDeviation);

    constructor(address _registry, uint256 _maxDeviation) {
        assert(_maxDeviation > 0);
        assert(_registry != address(0));

        registry = IChainlinkFeedRegistry(_registry);
        maxTimeDeviation = _maxDeviation;
    }

    function setMaxTimeDeviation(uint256 newDeviation) external onlyOwner {
        assert(maxTimeDeviation > 0);
        maxTimeDeviation = newDeviation;

        emit MaxTimeDeviationValueWasUpdated(newDeviation);
    }

    function getPrice(address base, address quote) public view returns (int256) {
        (
            ,
            /*uint80 roundID*/ int256 price,
            ,
            /*uint256 startedAt*/ uint256 timestamp /*uint80 answeredInRound*/,

        ) = registry.latestRoundData(base, quote);

        if (block.timestamp - timestamp > maxTimeDeviation) _priceFallback(base, quote);

        return price;
    }

    /// @dev can be overridden to implement custom logic
    function _priceFallback(address base, address quote) internal view returns (int256) {
        return 0;
    }
}
