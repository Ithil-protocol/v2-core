// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { FraxlendService } from "../../src/services/debit/FraxlendService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract FraxlendServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    FraxlendService internal immutable service;
    address internal constant frax = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address internal constant fraxLend = 0x2D0483FefAbA4325c7521539a3DFaCf94A19C472;
    IERC20 internal constant fraxToken = IERC20(frax);
    IERC4626 internal constant fraxLendToken = IERC4626(fraxLend);

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 151776455;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new FraxlendService(address(manager), fraxLend, 30 * 86400);

        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = frax;
        whales[loanTokens[0]] = 0x367a739ccC69940aF740590a7D533Ef8f96f282a;
        collateralTokens[0] = fraxLend;
        serviceAddress = address(service);
    }

    function testFraxlendIntegrationOpenPosition(uint256 amount, uint256 loan, uint256 margin) public {
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 transformedAmount = amount % whaleBalance;
        if (transformedAmount == 0) transformedAmount++;

        uint256 transformedMargin = (margin % (whaleBalance - transformedAmount));
        if (transformedMargin == 0) transformedMargin++;

        uint256 initialBalance = fraxLendToken.balanceOf(address(service));

        IService.Order memory order = _openOrder1(amount, loan, margin, 0, block.timestamp, "");

        order.agreement.collaterals[0].amount = fraxLendToken.convertToShares(
            order.agreement.loans[0].amount + order.agreement.loans[0].margin
        );

        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        assertEq(fraxLendToken.balanceOf(address(service)), initialBalance + collaterals[0].amount);
    }

    function testFraxlendIntegrationClosePosition(
        uint256 amount,
        uint256 loan,
        uint256 margin,
        uint256 minAmountsOut
    ) public {
        testFraxlendIntegrationOpenPosition(amount, loan, margin);

        bytes memory data = abi.encode(minAmountsOut);

        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        uint256 initialServiceBalance = fraxLendToken.balanceOf(address(service));
        uint256 toRedeem = fraxLendToken.convertToAssets(fraxLendToken.balanceOf(address(service)));
        if (toRedeem < minAmountsOut) {
            // Slippage check
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
            service.close(0, data);
        } else {
            uint256 initialBalance = fraxToken.balanceOf(address(this));
            service.close(0, data);
            assertEq(fraxToken.balanceOf(address(this)), initialBalance + toRedeem - actualLoans[0].amount);
            assertEq(fraxLendToken.balanceOf(address(service)), initialServiceBalance - collaterals[0].amount);
        }
    }

    function testFraxlendIntegrationQuoter(uint256 amount, uint256 loanTaken, uint256 margin) public {
        testFraxlendIntegrationOpenPosition(amount, loanTaken, margin);

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collaterals,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);

        uint256[] memory quoted = service.quote(agreement);

        uint256 initialBalance = IERC20(loanTokens[0]).balanceOf(address(this));

        service.close(0, abi.encode(0));
        uint256 expected = loan[0].amount > initialBalance + quoted[0]
            ? 0
            : initialBalance + quoted[0] - loan[0].amount;
        assertEq(IERC20(loanTokens[0]).balanceOf(address(this)), expected);
    }
}
