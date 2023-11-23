// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { IAToken } from "../../src/interfaces/external/aave/IAToken.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract AaveServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    AaveService internal immutable service;
    address internal constant aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new AaveService(address(manager), aavePool, 30 * 86400);

        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        whales[loanTokens[0]] = 0x252cd7185dB7C3689a571096D5B57D45681aA080;
        collateralTokens[0] = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
        serviceAddress = address(service);
    }

    function testAaveIntegrationOpenPosition(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin) public {
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 transformedAmount = daiAmount % whaleBalance;
        if (transformedAmount == 0) transformedAmount++;
        uint256 transformedMargin = (daiMargin % (whaleBalance - transformedAmount));
        if (transformedMargin == 0) transformedMargin++;
        IService.Order memory order = _openOrder1(daiAmount, daiLoan, daiMargin, 1, block.timestamp, "");
        uint256 initialAllowance = service.totalAllowance(collateralTokens[0]);
        uint256 initialBalance = IAToken(collateralTokens[0]).balanceOf(address(service));
        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        assertEq(service.totalAllowance(collateralTokens[0]), initialAllowance + collaterals[0].amount);
        assertEq(IAToken(collateralTokens[0]).balanceOf(address(service)), initialBalance + collaterals[0].amount);
        // In AaveV3 it's not 1:1, but it has at most a single unit of error
        assertGe(
            IAToken(collateralTokens[0]).balanceOf(address(service)) + 1,
            order.agreement.loans[0].amount + order.agreement.loans[0].margin
        );
        assertGe(
            order.agreement.loans[0].amount + order.agreement.loans[0].margin + 1,
            IAToken(collateralTokens[0]).balanceOf(address(service))
        );
    }

    function testAaveIntegrationTargetSupplyBorrow(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin) public {
        uint256 initialUserBalance = IERC20(loanTokens[0]).balanceOf(address(this));
        testAaveIntegrationOpenPosition(daiAmount, daiLoan, daiMargin);
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 supplyAmount = whaleBalance / 2;
        if (supplyAmount > 0) {
            vm.startPrank(whales[loanTokens[0]]);
            IERC20(loanTokens[0]).approve(aavePool, supplyAmount);
            aavePool.call(
                abi.encodeWithSignature(
                    "supply(address,uint256,address,uint16)",
                    loanTokens[0],
                    supplyAmount,
                    whales[loanTokens[0]],
                    0
                )
            );
            vm.warp(block.timestamp + 10000);
            // Simply supplying doesn't change anything: a borrow should occur
            aavePool.call(
                abi.encodeWithSignature(
                    "borrow(address,uint256,uint256,uint16,address)",
                    weth,
                    supplyAmount / 4000,
                    2,
                    0,
                    whales[loanTokens[0]]
                )
            );
            vm.warp(block.timestamp + 10000);
            vm.stopPrank();
        }

        bytes memory data = abi.encode(0);
        service.close(0, data);

        // Some fees must have been produced
        assertGe(IERC20(loanTokens[0]).balanceOf(address(this)), initialUserBalance);
    }

    function testAaveIntegrationClosePosition(
        uint256 daiAmount,
        uint256 daiLoan,
        uint256 daiMargin,
        uint256 minAmountsOutDai
    ) public {
        testAaveIntegrationOpenPosition(daiAmount, daiLoan, daiMargin);

        bytes memory data = abi.encode(minAmountsOutDai);

        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        if (collaterals[0].amount < minAmountsOutDai) {
            // Slippage check
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
            service.close(0, data);
        } else {
            uint256 initialBalance = IERC20(loanTokens[0]).balanceOf(address(this));
            uint256 initialServiceBalance = IERC20(collateralTokens[0]).balanceOf(address(service));
            uint256 initialAllowance = service.totalAllowance(collateralTokens[0]);
            uint256 toRedeem = IERC20(collateralTokens[0]).balanceOf(address(service)).safeMulDiv(
                collaterals[0].amount,
                initialAllowance
            );
            service.close(0, data);
            assertEq(IERC20(loanTokens[0]).balanceOf(address(this)), initialBalance + toRedeem - actualLoans[0].amount);
            assertEq(service.totalAllowance(collateralTokens[0]), initialAllowance - collaterals[0].amount);
            assertEq(
                IERC20(collateralTokens[0]).balanceOf(address(service)),
                initialServiceBalance - collaterals[0].amount
            );
        }
    }

    function testAaveIntegrationQuoter(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin) public {
        testAaveIntegrationOpenPosition(daiAmount, daiLoan, daiMargin);

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collaterals,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);

        uint256[] memory quoted = service.quote(agreement);

        uint256 initialBalance = IERC20(loanTokens[0]).balanceOf(address(this));
        // Allow any min amount
        service.close(0, abi.encode(0));

        assertEq(IERC20(loanTokens[0]).balanceOf(address(this)), initialBalance + quoted[0] - loan[0].amount);
    }
}
