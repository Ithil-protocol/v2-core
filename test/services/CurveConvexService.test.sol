// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IConvexBooster } from "../../src/interfaces/external/convex/IConvexBooster.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { CurveConvexService } from "../../src/services/debit/CurveConvexService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";
import { console2 } from "forge-std/console2.sol";

contract CurveConvexServiceTestRenBTCWBTC is BaseIntegrationServiceTest {
    CurveConvexService internal immutable service;

    address internal constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address internal constant curvePool = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
    uint256 internal constant convexPid = 6;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new CurveConvexService(address(manager), convexBooster, cvx);
        vm.stopPrank();
        loanLength = 2;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D; // renBTC
        loanTokens[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // wbtc
        whales[loanTokens[0]] = 0xaAde032DC41DbE499deBf54CFEe86d13358E9aFC;
        whales[loanTokens[1]] = 0x218B95BE3ed99141b0144Dba6cE88807c4AD7C09;
        collateralTokens[0] = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(curvePool, convexPid, loanTokens);
    }

    // _A()
    function _calculateA() internal view returns (uint256) {
        (, bytes memory t1Data) = curvePool.staticcall(abi.encodeWithSignature("future_A_time()"));
        uint256 t1 = abi.decode(t1Data, (uint256));
        (, bytes memory a1Data) = curvePool.staticcall(abi.encodeWithSignature("future_A()"));
        uint256 a1 = abi.decode(a1Data, (uint256));
        if (block.timestamp < t1) {
            (, bytes memory t0Data) = curvePool.staticcall(abi.encodeWithSignature("initial_A_time()"));
            uint256 t0 = abi.decode(t0Data, (uint256));
            (, bytes memory a0Data) = curvePool.staticcall(abi.encodeWithSignature("initial_A()"));
            uint256 a0 = abi.decode(a0Data, (uint256));
            if (a1 > a0) return a0 + ((a1 - a0) * (block.timestamp - t0)) / (t1 - t0);
            else return a0 - ((a0 - a1) * (block.timestamp - t0)) / (t1 - t0);
        } else return a1;
    }

    // WARNING! this is a simplification of the USELENDING array of Curve
    // which is an internal constant in Curve, thus different pools have different arrays
    // luckily we do not need this in the contract, but we should be careful in the frontend
    function _rates() internal view returns (uint256[2] memory) {
        (, bytes memory rateData) = loanTokens[0].staticcall(abi.encodeWithSignature("exchangeRateCurrent()"));
        return [(10**10) * abi.decode(rateData, (uint256)), 10**28];
    }

    function _xpMem(uint256[2] memory balances) internal view returns (uint256[2] memory) {
        uint256[2] memory rates = _rates();
        return [(rates[0] * balances[0]) / (10**18), (rates[1] * balances[1]) / (10**18)];
    }

    function _getDMem(uint256[2] memory balances) internal view returns (uint256) {
        uint256[2] memory xpmem = _xpMem(balances);
        uint256 s = xpmem[0] + xpmem[1];
        uint256 d = s;
        uint256 ann = _calculateA() * 2;
        for (uint i = 0; i < 256; i++) {
            uint256 dp = (((d * d) / (xpmem[0] * 2)) * d) / (xpmem[1] * 2); // Curve allows division by zero: "borking"
            uint256 dprev = d;
            d = ((ann * s + dp * 2) * d) / ((ann - 1) * d + 3 * dp);
            if (d > dprev)
                if (d - dprev <= 1) break;
                else if (dprev - d <= 1) break;
        }
        return d;
    }

    function _getBalances(int128 index) internal view returns (uint256) {
        (, bytes memory balanceData) = curvePool.staticcall(abi.encodeWithSignature("balances(int128)", index));
        return abi.decode(balanceData, (uint256));
    }

    function _calculateExpectedTokens(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        (, bytes memory feeData) = curvePool.staticcall(abi.encodeWithSignature("fee()"));
        uint256 fee = abi.decode(feeData, (uint256)) / 2;
        uint256[2] memory oldBalances = [_getBalances(0), _getBalances(1)];
        uint256 d0 = _getDMem([oldBalances[0], oldBalances[1]]);
        uint256[2] memory newBalances = [oldBalances[0] + amount0, oldBalances[1] + amount1];
        uint256 d1 = _getDMem([newBalances[0], newBalances[1]]);
        uint256 d2 = d1;
        for (uint256 i = 0; i < 2; i++) {
            uint256 idealBalance = (d1 * oldBalances[i]) / d0;
            uint256 difference = 0;
            if (idealBalance > newBalances[i]) difference = idealBalance - newBalances[i];
            else difference = newBalances[i] - idealBalance;
            newBalances[i] -= (fee * difference) / 10**10;
        }
        d2 = _getDMem(newBalances);
        return (IERC20(collateralTokens[0]).totalSupply() * (d2 - d0)) / d0;
    }

    function _getExtraReward(uint256 index) internal view returns (address) {
        IConvexBooster.PoolInfo memory poolInfo = IConvexBooster(convexBooster).poolInfo(convexPid);
        (, bytes memory extraRewardData) = poolInfo.crvRewards.staticcall(
            abi.encodeWithSignature("extraRewards(uint256)", index)
        );
        return abi.decode(extraRewardData, (address));
    }

    function _getExtraRewardLength() internal view returns (uint256) {
        IConvexBooster.PoolInfo memory poolInfo = IConvexBooster(convexBooster).poolInfo(convexPid);
        (, bytes memory extraRewardLengthData) = poolInfo.crvRewards.staticcall(
            abi.encodeWithSignature("extraRewardsLength()")
        );
        return abi.decode(extraRewardLengthData, (uint256));
    }

    function testOpen(uint256 amount0, uint256 loan0, uint256 margin0, uint256 amount1, uint256 loan1, uint256 margin1)
        public
    {
        IService.Order memory order = _openOrder2(
            amount0,
            loan0,
            margin0,
            amount1,
            loan1,
            margin1,
            0,
            block.timestamp,
            ""
        );
        uint256 expectedCollateral = _calculateExpectedTokens(
            order.agreement.loans[0].amount + order.agreement.loans[0].margin,
            order.agreement.loans[1].amount + order.agreement.loans[1].margin
        );
        IConvexBooster.PoolInfo memory poolInfo = IConvexBooster(convexBooster).poolInfo(convexPid);
        uint256 initialBalance = IERC20(collateralTokens[0]).balanceOf(address(service));
        uint256 initialRewardsBalance = IERC20(poolInfo.crvRewards).balanceOf(address(service));
        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        assertTrue(collaterals[0].amount == expectedCollateral);
        // No change: all the balance is deposited in Convex
        assertTrue(IERC20(collateralTokens[0]).balanceOf(address(service)) == initialBalance);
        assertTrue(
            IERC20(poolInfo.crvRewards).balanceOf(address(service)) == initialRewardsBalance + expectedCollateral
        );
    }

    function testClose(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1,
        uint256 minAmount1,
        uint256 minAmount2
    ) public {
        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);

        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        uint256[2] memory minAmountsOut = [minAmount1, minAmount2];
        bytes memory data = abi.encode(minAmountsOut);

        uint256 initialBalance0 = IERC20(loanTokens[0]).balanceOf(address(service));
        uint256 initialBalance1 = IERC20(loanTokens[1]).balanceOf(address(service));
        (uint256[] memory quoted, ) = service.quote(agreement);
        if (quoted[0] < minAmount1 || quoted[1] < minAmount2) {
            vm.expectRevert("Withdrawal resulted in fewer coins than expected");
            service.close(0, data);
        } else {
            service.close(0, data);
            assertTrue(IERC20(loanTokens[0]).balanceOf(address(service)) == initialBalance0 + quoted[0]);
            assertTrue(IERC20(loanTokens[1]).balanceOf(address(service)) == initialBalance1 + quoted[1]);
        }
    }
}
