// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManager } from "../../../interfaces/IManager.sol";
import { IOracle } from "../../../interfaces/IOracle.sol";
import { IFactory } from "../../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../../interfaces/external/wizardex/IPool.sol";
import { IGauge } from "../../../interfaces/external/balancer/IGauge.sol";
import { VaultHelper } from "../../../libraries/VaultHelper.sol";
import { IBalancerHarvester } from "../../../interfaces/IBalancerHarvester.sol";

contract BalancerHarvester is IBalancerHarvester {
    address public immutable owner;
    IOracle public immutable oracle;
    IFactory public immutable dex;
    IManager public immutable manager;
    address public immutable bal;

    constructor(address _oracle, address _dex, IManager _manager, address _bal) {
        oracle = IOracle(_oracle);
        dex = IFactory(_dex);
        manager = _manager;
        bal = _bal;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        assert(msg.sender == owner);
        _;
    }

    function harvest(address gauge, address[] memory tokens) external override onlyOwner {
        IGauge(gauge).claim_rewards(address(this));

        (address token, address vault) = VaultHelper.getBestVault(tokens, manager);
        // TODO check oracle
        uint256 price = oracle.getPrice(bal, token, 1);
        address dexPool = dex.pools(bal, token, 10); // TODO hardcoded tick
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(bal).balanceOf(address(this)), price, vault, block.timestamp + 1 weeks);

        // TODO add premium to the caller
    }
}
