// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBalancerPool } from "../../../interfaces/external/balancer/IBalancerPool.sol";
import { IBalancerVault } from "../../../interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerManager } from "../../../interfaces/IBalancerManager.sol";
import { IOracle } from "../../../interfaces/IOracle.sol";
import { IFactory } from "../../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../../interfaces/external/wizardex/IPool.sol";
import { IManager } from "../../../interfaces/IManager.sol";
import { IGauge } from "../../../interfaces/external/balancer/IGauge.sol";
import { IService } from "../../../interfaces/IService.sol";
import { VaultHelper } from "../../../libraries/VaultHelper.sol";
import { BalancerHelper } from "../../../libraries/BalancerHelper.sol";
import { console2 } from "forge-std/console2.sol";

contract BalancerManager is IBalancerManager {
    using SafeERC20 for IERC20;

    IBalancerVault internal immutable balancerVault;
    IOracle public immutable oracle;
    IFactory public immutable dex;
    IManager public immutable manager;
    address public immutable bal;

    mapping(address => PoolData) public pools;

    constructor(address _balancerVault, address _oracle, address _dex, IManager _manager, address _bal) {
        balancerVault = IBalancerVault(_balancerVault);
        oracle = IOracle(_oracle);
        dex = IFactory(_dex);
        manager = _manager;
        bal = _bal;
    }

    function getPool(address poolAddress) external view override returns (PoolData memory) {
        return pools[poolAddress];
    }

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external override {
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

    function removePool(address poolAddress) external override {
        PoolData memory pool = pools[poolAddress];
        assert(pools[poolAddress].length != 0);

        IERC20(poolAddress).approve(pool.gauge, 0);
        delete pools[poolAddress];

        emit PoolWasRemoved(poolAddress);
    }

    function harvest(address gauge, address[] memory tokens) external override {
        IGauge(gauge).claim_rewards(address(this));

        (address token, address vault) = VaultHelper.getBestVault(tokens, manager);
        // TODO check oracle
        uint256 price = oracle.getPrice(bal, token, 1);
        address dexPool = dex.pools(bal, token, 10); // TODO hardcoded tick
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(bal).balanceOf(address(this)), price, vault, block.timestamp + 1 weeks);

        // TODO add premium to the caller
    }

    function quote(
        IService.Agreement memory agreement,
        PoolData memory pool
    ) external view override returns (uint256[] memory) {
        (, uint256[] memory totalBalances, ) = balancerVault.getPoolTokens(pool.balancerPoolID);
        uint256[] memory amountsOut = new uint256[](agreement.loans.length);
        uint256[] memory profits;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            amountsOut[index] = agreement.loans[index].amount;
        }
        // Calculate needed BPT to repay loan + fees
        uint256 bptAmountOut = BalancerHelper.calculateExpectedBPTToExit(
            agreement.collaterals[0].token,
            totalBalances,
            amountsOut,
            pool.scalingFactors,
            pool.protocolFeeCollector,
            pool.maximumWeightIndex
        );

        // The remaining BPT is swapped to obtain profit
        // We need to update the balances since we virtually took tokens out of the pool
        // We also need to update the total supply since the bptOut were burned
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            totalBalances[index] -= amountsOut[index];
        }
        if (bptAmountOut < agreement.collaterals[0].amount) {
            profits = BalancerHelper.calculateExpectedTokensFromBPT(
                agreement.collaterals[0].token,
                pool.protocolFeeCollector,
                totalBalances,
                pool.scalingFactors,
                pool.weights,
                pool.maximumWeightIndex,
                agreement.collaterals[0].amount - bptAmountOut,
                IERC20(agreement.collaterals[0].token).totalSupply() - bptAmountOut
            );
            // Besides spurious tokens, also amountsOut had been obtained at the first exit
            for (uint256 index = 0; index < agreement.loans.length; index++) {
                profits[index] += amountsOut[index];
            }
        }

        return profits;
    }
}
