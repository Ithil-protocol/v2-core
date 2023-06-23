// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBalancerPool } from "../../../interfaces/external/balancer/IBalancerPool.sol";
import { IBalancerVault } from "../../../interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPoolManager } from "../../../interfaces/IBalancerPoolManager.sol";

contract BalancerPoolManager is IBalancerPoolManager {
    using SafeERC20 for IERC20;

    address public immutable owner;
    IBalancerVault internal immutable balancerVault;
    mapping(address => PoolData) public pools;

    constructor(address _balancerVault) {
        balancerVault = IBalancerVault(_balancerVault);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        assert(msg.sender == owner);
        _;
    }

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external override onlyOwner {
        assert(poolAddress != address(0));

        (address[] memory poolTokens, , ) = balancerVault.getPoolTokens(balancerPoolID);
        uint256 length = poolTokens.length;
        assert(length > 0);

        IBalancerPool bpool = IBalancerPool(poolAddress);
        bpool.approve(gauge, type(uint256).max);

        uint256 fee = bpool.getSwapFeePercentage();
        uint256[] memory weights = bpool.getNormalizedWeights();
        uint256 maxWeightTokenIndex = 0;
        uint256[] memory scalingFactors = new uint256[](length);

        for (uint8 i = 0; i < length; i++) {
            if (IERC20(poolTokens[i]).allowance(address(this), address(balancerVault)) == 0)
                IERC20(poolTokens[i]).safeApprove(address(balancerVault), type(uint256).max);
            if (weights[i] > weights[maxWeightTokenIndex]) maxWeightTokenIndex = i;
            scalingFactors[i] = 10 ** (18 - IERC20Metadata(poolTokens[i]).decimals());
        }

        pools[poolAddress] = PoolData(
            balancerPoolID,
            poolTokens,
            weights,
            scalingFactors,
            maxWeightTokenIndex,
            uint8(length),
            fee,
            gauge,
            balancerVault.getProtocolFeesCollector()
        );

        emit PoolWasAdded(poolAddress);
    }

    function removePool(address poolAddress) external override onlyOwner {
        PoolData memory pool = pools[poolAddress];
        assert(pools[poolAddress].length != 0);

        IERC20(poolAddress).approve(pool.gauge, 0);
        delete pools[poolAddress];

        emit PoolWasRemoved(poolAddress);
    }
}
