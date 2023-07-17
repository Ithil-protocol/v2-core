// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../interfaces/external/wizardex/IPool.sol";
import { IBalancerVault } from "../../interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "../../interfaces/external/balancer/IBalancerPool.sol";
import { IProtocolFeesCollector } from "../../interfaces/external/balancer/IProtocolFeesCollector.sol";
import { IGauge } from "../../interfaces/external/balancer/IGauge.sol";
import { BalancerHelper } from "../../libraries/BalancerHelper.sol";
import { WeightedMath } from "../../libraries/external/Balancer/WeightedMath.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { IBalancerManager, BalancerManager } from "./utils/BalancerManager.sol";
import { Service } from "../Service.sol";
import { DebitService } from "../DebitService.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    BalancerService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Balancer pool
contract BalancerService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBalancerPool;

    error InexistentPool();
    error TokenIndexMismatch();
    error SlippageError();

    address internal immutable poolManager;
    IBalancerVault internal immutable balancerVault;
    uint256 public rewardRate;
    address public immutable bal;
    address public immutable oracle;
    address public immutable dex;
    mapping(address => IBalancerManager.PoolData) public pools;

    constructor(
        address _manager,
        address _oracle,
        address _factory,
        address _balancerVault,
        address _bal,
        uint256 _deadline
    ) Service("BalancerService", "BALANCER-SERVICE", _manager, _deadline) {
        oracle = _oracle;
        dex = _factory;
        balancerVault = IBalancerVault(_balancerVault);
        bal = _bal;

        poolManager = address(new BalancerManager(_balancerVault, _oracle, _factory, manager, bal));
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        (bool success, bytes memory data) = poolManager.delegatecall(
            abi.encodeWithSelector(IBalancerManager.getPool.selector, agreement.collaterals[0].token)
        );
        IBalancerManager.PoolData memory pool = abi.decode(data, (IBalancerManager.PoolData));
        if (success == false || pool.length == 0) revert InexistentPool();

        uint256[] memory amountsIn = new uint256[](agreement.loans.length);
        address[] memory tokens = new address[](agreement.loans.length);

        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
            amountsIn[index] = agreement.loans[index].amount + agreement.loans[index].margin;
        }
        IERC20 bpToken = IERC20(agreement.collaterals[0].token);
        uint256 bptInitialBalance = bpToken.balanceOf(address(this));

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsIn,
                agreement.collaterals[0].amount
            ),
            fromInternalBalance: false
        });
        balancerVault.joinPool(pool.balancerPoolID, address(this), address(this), request);

        agreement.collaterals[0].amount = bpToken.balanceOf(address(this)) - bptInitialBalance;
        if (pool.gauge != address(0)) IGauge(pool.gauge).deposit(agreement.collaterals[0].amount);
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        (bool success, bytes memory data) = poolManager.delegatecall(
            abi.encodeWithSelector(IBalancerManager.getPool.selector, agreement.collaterals[0].token)
        );
        assert(success);
        IBalancerManager.PoolData memory pool = abi.decode(data, (IBalancerManager.PoolData));

        // TODO: add check on fees to be sure amountOut is not too little
        if (pool.gauge != address(0)) IGauge(pool.gauge).withdraw(agreement.collaterals[0].amount, true);
        address[] memory tokens = new address[](agreement.loans.length);
        (uint256[] memory minAmountsOut, bytes memory swapData) = abi.decode(data, (uint256[], bytes));
        bool slippageEnforced = true;
        for (uint256 index = 0; index < agreement.loans.length; index++) {
            tokens[index] = agreement.loans[index].token;
            if (tokens[index] != pool.tokens[index]) revert TokenIndexMismatch();
            if (minAmountsOut[index] <= agreement.loans[index].amount) {
                slippageEnforced = false;
                minAmountsOut[index] = agreement.loans[index].amount;
            }
        }

        uint256 spentBpt = IERC20(agreement.collaterals[0].token).balanceOf(address(this));
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(2, minAmountsOut, agreement.collaterals[0].amount),
            toInternalBalance: false
        });
        // If possible, try to obtain the minAmountsOut
        try balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request) {
            spentBpt -= IERC20(agreement.collaterals[0].token).balanceOf(address(this));
            assert(spentBpt <= agreement.collaterals[0].amount);
        } catch {
            // It is not possible to obtain minAmountsOut
            // This could be a bad repay event but also a too strict slippage on user side
            // In the latter case, we simply revert
            if (slippageEnforced) revert SlippageError();
            spentBpt = 0;
        }
        // Swap residual BPT for whatever the Balancer pool gives back and repay sender
        // This is done also if slippage is not enforced and the first exit failed
        // In this case we are on a bad liquidation
        request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: new uint256[](agreement.loans.length),
            userData: abi.encode(1, agreement.collaterals[0].amount - spentBpt),
            toInternalBalance: false
        });
        balancerVault.exitPool(pool.balancerPoolID, address(this), payable(address(this)), request);
    }

    // bug: this quote has a branch which always returns zero
    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        IBalancerManager.PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.length == 0) revert InexistentPool();

        uint256[] memory profits = IBalancerManager(poolManager).quote(agreement, pool);

        return profits;
    }

    function harvest(address poolAddress) external {
        (bool success, bytes memory data) = poolManager.delegatecall(
            abi.encodeWithSelector(IBalancerManager.harvest.selector, poolAddress)
        );
        assert(success);
    }

    function addPool(address poolAddress, bytes32 balancerPoolID, address gauge) external onlyOwner {
        // We need a delegate call as we are giving tokens approvals
        (bool success, bytes memory data) = poolManager.delegatecall(
            abi.encodeWithSelector(IBalancerManager.addPool.selector, poolAddress, balancerPoolID, gauge)
        );
        assert(success);
    }

    function removePool(address poolAddress) external onlyOwner {
        (bool success, bytes memory data) = poolManager.delegatecall(
            abi.encodeWithSelector(IBalancerManager.removePool.selector, poolAddress)
        );
        assert(success);
    }
}
