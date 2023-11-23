// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { AngleService } from "../../src/services/debit/AngleService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract AngleServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    AngleService internal immutable service;
    address internal constant agEur = 0xFA5Ed56A203466CbBC2430a43c66b9D8723528E7;
    address internal constant stEur = 0x004626A008B1aCdC4c74ab51644093b155e59A23;
    IERC20 internal constant agEurToken = IERC20(agEur);
    IERC4626 internal constant stEurToken = IERC4626(stEur);

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 151776455;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new AngleService(address(manager), stEur, 30 * 86400);

        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = agEur;
        whales[loanTokens[0]] = 0xE4D9FaDDd9bcA5D8393BeE915dC56E916AB94d27;
        collateralTokens[0] = stEur;
        serviceAddress = address(service);
    }

    function testAngleIntegrationOpenPosition(uint256 agEurAmount, uint256 agEurLoan, uint256 agEurMargin) public {
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 transformedAmount = agEurAmount % whaleBalance;
        if (transformedAmount == 0) transformedAmount++;

        uint256 transformedMargin = (agEurMargin % (whaleBalance - transformedAmount));
        if (transformedMargin == 0) transformedMargin++;

        uint256 initialBalance = stEurToken.balanceOf(address(service));

        IService.Order memory order = _openOrder1(agEurAmount, agEurLoan, agEurMargin, 0, block.timestamp, "");

        order.agreement.collaterals[0].amount = stEurToken.convertToShares(
            order.agreement.loans[0].amount + order.agreement.loans[0].margin
        );

        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        assertEq(stEurToken.balanceOf(address(service)), initialBalance + collaterals[0].amount);
    }

    function testAngleIntegrationClosePosition(
        uint256 agEurAmount,
        uint256 agEurLoan,
        uint256 agEurMargin,
        uint256 minAmountsOut
    ) public {
        testAngleIntegrationOpenPosition(agEurAmount, agEurLoan, agEurMargin);

        bytes memory data = abi.encode(minAmountsOut);

        uint256 initialServiceBalance = stEurToken.balanceOf(address(service));
        uint256 toRedeem = stEurToken.convertToAssets(stEurToken.balanceOf(address(service)));
        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        if (toRedeem < minAmountsOut) {
            // Slippage check
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
            service.close(0, data);
        } else {
            uint256 initialBalance = agEurToken.balanceOf(address(this));
            service.close(0, data);
            assertEq(agEurToken.balanceOf(address(this)), initialBalance + toRedeem - actualLoans[0].amount);
            assertEq(stEurToken.balanceOf(address(service)), initialServiceBalance - collaterals[0].amount);
        }
    }

    function testAngleIntegrationQuoter(uint256 agEurAmount, uint256 agEurLoan, uint256 agEurMargin) public {
        testAngleIntegrationOpenPosition(agEurAmount, agEurLoan, agEurMargin);

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
