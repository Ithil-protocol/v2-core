// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router } from "../../interfaces/external/sushi/IUniswapV2Router.sol";
import { IUniswapV2Factory } from "../../interfaces/external/sushi/IUniswapV2Factory.sol";
import { IMiniChef } from "../../interfaces/external/sushi/IMiniChef.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { Math } from "../../libraries/external/Uniswap/Math.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

/// @title    SushiService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Sushi pool
contract SushiService is SecuritisableService {
    using GeneralMath for uint256;
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

    mapping(address => PoolData) public pools;
    IUniswapV2Router public immutable router;
    IMiniChef public immutable minichef;
    address public immutable rewardToken;

    constructor(address _manager, address _router, address _minichef)
        Service("SushiService", "SUSHI-SERVICE", _manager)
    {
        router = IUniswapV2Router(_router);
        minichef = IMiniChef(_minichef);
        rewardToken = minichef.SUSHI();
    }

    function _open(Agreement memory agreement, bytes calldata data) internal override {
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
            block.timestamp // @todo pass via bytes data ?
        );

        agreement.collaterals[0].amount = liquidity;
        minichef.deposit(pool.poolID, liquidity, address(this));
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
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
            block.timestamp // @todo pass via bytes data ?
        );
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory, uint256[] memory) {
        uint256[] memory fees = new uint256[](agreement.loans.length);
        uint256[] memory quoted = new uint256[](agreement.loans.length);
        uint256 balanceA = IERC20(agreement.loans[0].token).balanceOf(agreement.collaterals[0].token);
        uint256 balanceB = IERC20(agreement.loans[1].token).balanceOf(agreement.collaterals[0].token);
        uint256 totalSupply = IERC20(agreement.collaterals[0].token).totalSupply();
        (, bytes memory klast) = agreement.collaterals[0].token.staticcall(abi.encodeWithSignature("kLast()"));
        // Todo: add fees
        uint256 rootK = Math.sqrt(balanceA + agreement.loans[0].amount) * (balanceB + agreement.loans[1].amount);
        uint256 rootKLast = Math.sqrt(abi.decode(klast, (uint256)));
        totalSupply += (totalSupply * (rootK - rootKLast)) / (5 * rootK + rootKLast);
        quoted[0] = (agreement.collaterals[0].amount * balanceA) / totalSupply;
        quoted[1] = (agreement.collaterals[0].amount * balanceB) / totalSupply;
        return (fees, quoted);
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
        IERC20(lpToken).approve(address(minichef), 0);

        emit PoolWasRemoved(pools[lpToken].poolID);

        delete pools[lpToken];
    }
}
