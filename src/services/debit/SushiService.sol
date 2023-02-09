// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router } from "../../interfaces/external/sushi/IUniswapV2Router.sol";
import { IMiniChef } from "../../interfaces/external/sushi/IMiniChef.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

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

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {}

    function addPool(address lpToken, uint256 poolID, address[2] calldata tokens) external onlyOwner {
        assert(tokens[0] < tokens[1]);

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
