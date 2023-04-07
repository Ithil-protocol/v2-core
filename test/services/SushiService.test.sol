// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Oracle } from "../../src/Oracle.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { SushiService } from "../../src/services/debit/SushiService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { Math } from "../../src/libraries/external/Uniswap/Math.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract SushiServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    SushiService internal immutable service;

    address internal constant sushiRouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant minichef = 0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3;
    uint256 internal constant poolID = 0;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 76395332;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new SushiService(address(manager), address(oracle), address(dex), sushiRouter, minichef, 30 * 86400);

        loanLength = 2;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // weth
        loanTokens[1] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // usdc
        whales[loanTokens[0]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        whales[loanTokens[1]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        collateralTokens[0] = 0x905dfCD5649217c42684f23958568e533C711Aa3;
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(poolID, [loanTokens[0], loanTokens[1]]);
    }

    function _calculateDeposit(uint256 usdcLoan, uint256 usdcMargin, uint256 wethLoan, uint256 wethMargin)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        (, bytes memory wethQuotedData) = sushiRouter.staticcall(
            abi.encodeWithSignature(
                "quote(uint256,uint256,uint256)",
                wethMargin + wethLoan,
                IERC20(loanTokens[0]).balanceOf(collateralTokens[0]),
                IERC20(loanTokens[1]).balanceOf(collateralTokens[0])
            )
        );
        (, bytes memory usdcQuotedData) = sushiRouter.staticcall(
            abi.encodeWithSignature(
                "quote(uint256,uint256,uint256)",
                usdcMargin + usdcLoan,
                IERC20(loanTokens[1]).balanceOf(collateralTokens[0]),
                IERC20(loanTokens[0]).balanceOf(collateralTokens[0])
            )
        );
        uint256 amountA;
        uint256 amountB;
        if (abi.decode(wethQuotedData, (uint256)) <= usdcLoan + usdcMargin) {
            (amountA, amountB) = (wethLoan + wethMargin, abi.decode(wethQuotedData, (uint256)));
        } else {
            (amountA, amountB) = (abi.decode(usdcQuotedData, (uint256)), usdcLoan + usdcMargin);
        }
        return (amountA, amountB, _calculateFees(amountA, amountB));
    }

    function _calculateFees(uint256 amountA, uint256 amountB) internal view returns (uint256) {
        (, bytes memory klast) = collateralTokens[0].staticcall(abi.encodeWithSignature("kLast()"));
        uint256 rootK = Math.sqrt(
            (IERC20(loanTokens[1]).balanceOf(collateralTokens[0]) + amountA) *
                (IERC20(loanTokens[0]).balanceOf(collateralTokens[0]) + amountB)
        );
        uint256 rootKLast = Math.sqrt(abi.decode(klast, (uint256)));
        return (IERC20(collateralTokens[0]).totalSupply() * (rootK - rootKLast)) / (5 * rootK + rootKLast);
    }

    function testSushiIntegrationOpenPosition(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1
    ) public returns (bool) {
        IService.Order memory order = _openOrder2(
            amount0,
            loan0,
            margin0,
            amount1,
            loan1,
            margin1,
            0,
            block.timestamp,
            abi.encode([uint256(0), uint256(0)])
        );
        (uint256 wethQuoted, uint256 usdcQuoted, uint256 fees) = _calculateDeposit(
            order.agreement.loans[1].amount,
            order.agreement.loans[1].margin,
            order.agreement.loans[0].amount,
            order.agreement.loans[0].margin
        );
        bool success = true;
        if (
            wethQuoted * (IERC20(collateralTokens[0]).totalSupply() + fees) <
            IERC20(loanTokens[0]).balanceOf(collateralTokens[0]) ||
            usdcQuoted * (IERC20(collateralTokens[0]).totalSupply() + fees) <
            IERC20(loanTokens[1]).balanceOf(collateralTokens[0])
        ) {
            vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
            service.open(order);
            success = false;
        } else service.open(order);
        return success;
    }

    function testSushiIntegrationClosePosition(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1
    ) public {
        bool success = testSushiIntegrationOpenPosition(amount0, loan0, margin0, amount1, loan1, margin1);

        uint256[] memory minAmountsOut = new uint256[](2);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;
        bytes memory data = abi.encode(minAmountsOut);

        if (success) {
            (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);

            uint256 balanceWeth = IERC20(loanTokens[0]).balanceOf(collateralTokens[0]);
            uint256 balanceUsdc = IERC20(loanTokens[1]).balanceOf(collateralTokens[0]);
            uint256 fees = _calculateFees(balanceWeth, balanceUsdc);
            uint256 totalSupply = IERC20(collateralTokens[0]).totalSupply() + fees;
            if (
                collaterals[0].amount * balanceWeth < totalSupply || collaterals[0].amount * balanceUsdc < totalSupply
            ) {
                vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
                service.close(0, data);
            } else service.close(0, data);
        }
    }

    function testSushiIntegrationQuoter(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1
    ) public {
        bool success = testSushiIntegrationOpenPosition(amount0, loan0, margin0, amount1, loan1, margin1);
        if (success) {
            (
                IService.Loan[] memory loan,
                IService.Collateral[] memory collaterals,
                uint256 createdAt,
                IService.Status status
            ) = service.getAgreement(1);

            IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);

            (uint256[] memory profits, ) = service.quote(agreement); // TODO test quoter
        }
    }
}
