// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../interfaces/external/wizardex/IPool.sol";
import { IUniswapV2Router } from "../../interfaces/external/sushi/IUniswapV2Router.sol";
import { IUniswapV2Factory } from "../../interfaces/external/sushi/IUniswapV2Factory.sol";
import { IMiniChef } from "../../interfaces/external/sushi/IMiniChef.sol";
import { VaultHelper } from "../../libraries/VaultHelper.sol";
import { Math } from "../../libraries/external/Uniswap/Math.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    SushiService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Sushi pool
contract SushiService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    struct PoolData {
        uint256 poolID;
        address[2] tokens;
    }

    event PoolWasAdded(uint256 indexed poolID);
    event PoolWasRemoved(uint256 indexed poolID);

    error TokenIndexMismatch();
    error InexistentPool();
    error InvalidInput();
    error SushiLPMismatch();
    error WrongTokenOrder();
    error ZeroTotalSupply();

    mapping(address => PoolData) public pools;
    IUniswapV2Router public immutable router;
    IMiniChef public immutable minichef;
    address public immutable sushi;
    IOracle public immutable oracle;
    IFactory public immutable factory;

    constructor(
        address _manager,
        address _oracle,
        address _factory,
        address _router,
        address _minichef,
        uint256 _deadline
    ) Service("SushiService", "SUSHI-SERVICE", _manager, _deadline) {
        oracle = IOracle(_oracle);
        factory = IFactory(_factory);
        router = IUniswapV2Router(_router);
        minichef = IMiniChef(_minichef);
        sushi = minichef.SUSHI();
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        if (pool.tokens.length != 2) revert InexistentPool();
        if (agreement.loans.length != 2) revert InvalidInput();

        uint256[] memory amountsIn = new uint256[](2);
        for (uint256 index = 0; index < 2; index++) {
            if (agreement.loans[index].token != pool.tokens[index]) revert TokenIndexMismatch();
            amountsIn[index] = agreement.loans[index].amount + agreement.loans[index].margin;
        }

        uint256[2] memory minAmountsOut = abi.decode(data, (uint256[2]));
        (, , uint256 liquidity) = router.addLiquidity(
            agreement.loans[0].token,
            agreement.loans[1].token,
            amountsIn[0],
            amountsIn[1],
            minAmountsOut[0],
            minAmountsOut[1],
            address(this),
            block.timestamp // TODO pass via bytes data ?
        );

        agreement.collaterals[0].amount = liquidity;
        minichef.deposit(pool.poolID, liquidity, address(this));
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        PoolData memory pool = pools[agreement.collaterals[0].token];
        minichef.withdraw(pool.poolID, agreement.collaterals[0].amount, address(this));

        uint256[] memory minAmountsOut = abi.decode(data, (uint256[]));
        IERC20(agreement.collaterals[0].token).approve(address(router), agreement.collaterals[0].amount);
        router.removeLiquidity(
            agreement.loans[0].token,
            agreement.loans[1].token,
            agreement.collaterals[0].amount,
            minAmountsOut[0],
            minAmountsOut[1],
            address(this),
            block.timestamp // TODO pass via bytes data ?
        );

        // TODO swap SUSHI for collateral tokens
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory quoted = new uint256[](agreement.loans.length);
        uint256 balanceA = IERC20(agreement.loans[0].token).balanceOf(agreement.collaterals[0].token);
        uint256 balanceB = IERC20(agreement.loans[1].token).balanceOf(agreement.collaterals[0].token);
        uint256 totalSupply = IERC20(agreement.collaterals[0].token).totalSupply();
        (, bytes memory klast) = agreement.collaterals[0].token.staticcall(abi.encodeWithSignature("kLast()"));

        uint256 rootK = Math.sqrt(balanceA + agreement.loans[0].amount) * (balanceB + agreement.loans[1].amount);
        uint256 rootKLast = Math.sqrt(abi.decode(klast, (uint256)));
        totalSupply += (totalSupply * (rootK - rootKLast)) / (5 * rootK + rootKLast);
        if (totalSupply == 0) revert ZeroTotalSupply();
        quoted[0] = (agreement.collaterals[0].amount * balanceA) / totalSupply;
        quoted[1] = (agreement.collaterals[0].amount * balanceB) / totalSupply;

        return quoted;
    }

    function addPool(uint256 poolID, address[2] calldata tokens) external onlyOwner {
        if (tokens[0] >= tokens[1]) revert WrongTokenOrder();
        address lpToken = IUniswapV2Factory(router.factory()).getPair(tokens[0], tokens[1]);
        if (minichef.lpToken(poolID) != lpToken) revert SushiLPMismatch();

        for (uint8 i = 0; i < 2; i++) {
            if (IERC20(tokens[i]).allowance(address(this), address(router)) == 0)
                IERC20(tokens[i]).safeApprove(address(router), type(uint256).max);
        }
        IERC20(lpToken).safeApprove(address(minichef), type(uint256).max);

        pools[lpToken] = PoolData(poolID, tokens);

        emit PoolWasAdded(poolID);
    }

    function removePool(address lpToken) external onlyOwner {
        PoolData memory pool = pools[lpToken];
        if (pool.tokens.length != 2) revert InexistentPool();

        IERC20(lpToken).approve(address(minichef), 0);

        delete pools[lpToken];

        emit PoolWasRemoved(pools[lpToken].poolID);
    }

    function harvest(address poolAddress) external {
        PoolData memory pool = pools[poolAddress];
        if (pool.tokens.length != 2) revert InexistentPool();

        minichef.harvest(pool.poolID, address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = sushi;
        (address token, address vault) = VaultHelper.getBestVault(tokens, manager);

        // TODO check oracle
        uint256 price = oracle.getPrice(sushi, token, 1);
        address dexPool = factory.pools(sushi, token, 10); // TODO hardcoded tick
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(sushi).balanceOf(address(this)), price, vault, block.timestamp + 30 days);

        // TODO add premium to the caller
    }
}
