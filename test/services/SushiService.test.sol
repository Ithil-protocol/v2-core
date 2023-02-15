// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { SushiService } from "../../src/services/debit/SushiService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { Math } from "../../src/libraries/external/Uniswap/Math.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract SushiServiceTest is BaseServiceTest {
    using GeneralMath for uint256;

    SushiService internal immutable service;
    address internal constant sushirouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant minichef = 0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3;
    uint256 internal constant poolID = 0;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 55895589;

    constructor() BaseServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new SushiService(address(manager), sushirouter, minichef);
        vm.stopPrank();
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
        (, bytes memory wethQuotedData) = sushirouter.staticcall(
            abi.encodeWithSignature(
                "quote(uint256,uint256,uint256)",
                wethMargin + wethLoan,
                IERC20(loanTokens[0]).balanceOf(collateralTokens[0]),
                IERC20(loanTokens[1]).balanceOf(collateralTokens[0])
            )
        );
        (, bytes memory usdcQuotedData) = sushirouter.staticcall(
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

    function _openOrder(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) internal returns (bool) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        amounts[0] = wethAmount;
        loans[0] = wethLoan;
        margins[0] = wethMargin;
        amounts[1] = usdcAmount;
        loans[1] = usdcLoan;
        margins[1] = usdcMargin;
        IService.Order memory order = _prepareOpenOrder(
            amounts,
            loans,
            margins,
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

    function testOpen(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) public returns (bool) {
        return _openOrder(usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin);
    }

    function testClose(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        bool success = testOpen(usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin);

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

    function testQuote(
        uint256 usdcAmount,
        uint256 usdcLoan,
        uint256 usdcMargin,
        uint256 wethAmount,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        bool success = testOpen(usdcAmount, usdcLoan, usdcMargin, wethAmount, wethLoan, wethMargin);
        if (success) {
            (
                IService.Loan[] memory loan,
                IService.Collateral[] memory collaterals,
                uint256 createdAt,
                IService.Status status
            ) = service.getAgreement(1);

            IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);

            (uint256[] memory profits, ) = service.quote(agreement);
        }
    }
}
