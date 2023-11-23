// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IBalancerVault } from "../../src/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "../../src/interfaces/external/balancer/IBalancerPool.sol";
import { BalancerService } from "../../src/services/debit/BalancerService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { WeightedMath } from "../../src/libraries/external/Balancer/WeightedMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { StringEncoder } from "../helpers/StringEncoder.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

/// @dev State study
/// BalancerService native state:
/// mapping(address => PoolData) public pools;
/// IBalancerVault internal immutable balancerVault;
/// address public immutable rewardToken; (this is just BAL)

/// - BalancerService is SecuritisableService:
/// mapping(uint256 => address) public lenders;

/// - SecuritisableService is DebitService:
/// None

/// - DebitService is Service:
/// IManager public immutable manager;
/// address public guardian;
/// mapping(address => uint256) public exposures;
/// Agreement[] public agreements;
/// bool public locked;
/// uint256 public id;

/// @dev overrides (except first implementation of virtual functions)
///

// contract BalancerServiceWeightedOHMWETH is BalancerServiceWeightedDAIWETH {
//     using GeneralMath for uint256;

//     // address internal constant auraPoolID = 2;

//     function setUp() public override {
//         loanTokens[0] = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5; // ohm
//         loanTokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
//         whales[loanTokens[0]] = 0x64C0fe73Dff66a8b9b803A1796082a575899DD26;
//         whales[loanTokens[1]] = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
//         collateralTokens[0] = 0xD1eC5e215E8148D76F4460e4097FD3d5ae0A3558; // Pool 50 OHM - 50 WETH
//         balancerPoolID = 0xd1ec5e215e8148d76f4460e4097fd3d5ae0a35580002000000000000000003d3;
//         gauge = address(0);
//         super.setUp();
//     }
// }

contract BalancerServiceWeightedTriPool is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    BalancerService internal immutable service;

    address internal constant router = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal constant balancerPoolID = 0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002;
    address internal constant gauge = 0x104f1459a2fFEa528121759B238BB609034C2f01;
    address internal constant bal = 0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8;
    address internal constant gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    // address internal constant weightedMath = 0x37aaA5c2925b6A30D76a3D4b6C7D2a9137F02dc2;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new BalancerService(address(manager), address(oracle), address(dex), balancerVault, bal, 86400 * 30);

        loanLength = 3;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // wbtc
        loanTokens[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // weth
        loanTokens[2] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // usdc

        whales[loanTokens[0]] = gmxVault;
        whales[loanTokens[1]] = gmxVault;
        whales[loanTokens[2]] = gmxVault;
        collateralTokens[0] = 0x64541216bAFFFEec8ea535BB71Fbc927831d0595; // Pool 33 WBTC - 33 WETH - 33 USDC
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(collateralTokens[0], balancerPoolID, gauge);
    }

    function _upscaleArray(uint256[] memory array) internal view {
        for (uint256 i = 0; i < loanLength; i++) {
            // Tokens with more than 18 decimals are not supported.
            uint256 decimalsDifference = 18 - IERC20Metadata(address(loanTokens[i])).decimals();
            array[i] *= 10 ** decimalsDifference;
        }
    }

    function _downscaleArray(uint256[] memory array) internal view {
        for (uint256 i = 0; i < loanLength; i++) {
            // Tokens with more than 18 decimals are not supported.
            uint256 decimalsDifference = 18 - IERC20Metadata(address(loanTokens[i])).decimals();
            array[i] /= 10 ** decimalsDifference;
        }
    }

    function _modifyBalancesWithFees(uint256[] memory balances, uint256[] memory normalizedWeights) internal view {
        _upscaleArray(balances);
        uint256 invariantBeforeJoin = WeightedMath._calculateInvariant(normalizedWeights, balances);
        uint256 lastInvariant = IBalancerPool(collateralTokens[0]).getLastInvariant();

        (, bytes memory feesData) = IBalancerVault(balancerVault).getProtocolFeesCollector().staticcall(
            abi.encodeWithSignature("getSwapFeePercentage()")
        );
        uint256 protocolSwapFees = abi.decode(feesData, (uint256));
        uint256 maxWeightTokenIndex = 0;

        for (uint256 i = 1; i < loanLength; i++) {
            if (normalizedWeights[i] > normalizedWeights[maxWeightTokenIndex]) maxWeightTokenIndex = i;
        }

        uint256[] memory dueProtocolFeeAmounts = new uint256[](loanLength);
        dueProtocolFeeAmounts[maxWeightTokenIndex] = WeightedMath._calcDueTokenProtocolSwapFeeAmount(
            balances[maxWeightTokenIndex],
            normalizedWeights[maxWeightTokenIndex],
            lastInvariant,
            invariantBeforeJoin,
            protocolSwapFees
        );
        balances[maxWeightTokenIndex] -= dueProtocolFeeAmounts[maxWeightTokenIndex];
    }

    function _calculateExpectedBPTFromJoin(
        uint256[] memory balances,
        uint256[] memory amountsIn
    ) internal view returns (uint256) {
        uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
        _modifyBalancesWithFees(balances, normalizedWeights);
        _upscaleArray(amountsIn);
        uint256 amountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            normalizedWeights,
            amountsIn,
            IERC20(collateralTokens[0]).totalSupply(),
            IBalancerPool(collateralTokens[0]).getSwapFeePercentage()
        );
        _downscaleArray(amountsIn);
        _downscaleArray(balances);
        return amountOut;
    }

    function _calculateExpectedBPTToExit(
        uint256[] memory balances,
        uint256[] memory amountsOut
    ) internal view returns (uint256) {
        uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
        _modifyBalancesWithFees(balances, normalizedWeights);
        _upscaleArray(amountsOut);
        uint256 expectedBpt = WeightedMath._calcBptInGivenExactTokensOut(
            balances,
            normalizedWeights,
            amountsOut,
            IERC20(collateralTokens[0]).totalSupply(),
            IBalancerPool(collateralTokens[0]).getSwapFeePercentage()
        );
        _downscaleArray(amountsOut);
        _downscaleArray(balances);
        return expectedBpt;
    }

    function _calculateExpectedTokensFromBPT(
        uint256[] memory balances,
        uint256 amount,
        uint256 totalSupply
    ) internal view returns (uint256[] memory) {
        uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
        _modifyBalancesWithFees(balances, normalizedWeights);
        uint256[] memory expectedTokens = WeightedMath._calcTokensOutGivenExactBptIn(balances, amount, totalSupply);
        _downscaleArray(balances);
        _downscaleArray(expectedTokens);
        return expectedTokens;
    }

    function testBalancerIntegrationOpenPosition(
        uint256 loan0,
        uint256 margin0,
        uint256 loan1,
        uint256 margin1,
        uint256 loan2,
        uint256 margin2
    ) public {
        IService.Order memory order = _openOrder3(
            loan0,
            margin0,
            loan1,
            margin1,
            loan2,
            margin2,
            0,
            block.timestamp,
            ""
        );
        uint256[] memory amountsIn = new uint256[](loanLength);
        for (uint256 i = 0; i < loanLength; i++) {
            amountsIn[i] = order.agreement.loans[i].amount + order.agreement.loans[i].margin;
        }
        (, uint256[] memory balances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        uint256 expectedTokens = _calculateExpectedBPTFromJoin(balances, amountsIn);
        service.open(order);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);

        assertEq(collaterals[0].amount, expectedTokens);
        // Gauge token is 1:1 both at deposit and withdraw
        assertEq(IERC20(gauge).balanceOf(address(service)), expectedTokens);
    }

    function testBalancerIntegrationClosePosition(
        uint256 loan0,
        uint256 margin0,
        uint256 loan1,
        uint256 margin1,
        uint256 loan2,
        uint256 margin2,
        uint256 minAmountsOut0,
        uint256 minAmountsOut1,
        uint256 minAmountsOut2
    ) internal {
        // TODO: activate
        testBalancerIntegrationOpenPosition(loan0, margin0, loan1, margin1, loan2, margin2);

        (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        minAmountsOut0 = minAmountsOut0 % (1 + totalBalances[0] / 2);
        minAmountsOut1 = minAmountsOut1 % (1 + totalBalances[1] / 2);
        minAmountsOut2 = minAmountsOut2 % (1 + totalBalances[2] / 2);

        uint256[] memory initialBalances = new uint256[](loanLength);
        for (uint256 i = 0; i < loanLength; i++) {
            initialBalances[i] = IERC20(loanTokens[i]).balanceOf(address(service));
        }

        uint256 bptTotalSupply = IERC20(collateralTokens[0]).totalSupply();
        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);

        bytes memory swapData;
        uint256[] memory minAmountsOut = new uint256[](3);
        // Fees make the initial investment always at a loss
        minAmountsOut[0] = minAmountsOut0;
        minAmountsOut[1] = minAmountsOut1;
        minAmountsOut[2] = minAmountsOut2;
        bytes memory data = abi.encode(minAmountsOut, swapData);
        (, uint256[] memory balances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        if (
            minAmountsOut0 > actualLoans[0].amount &&
            minAmountsOut1 > actualLoans[1].amount &&
            minAmountsOut2 > actualLoans[2].amount &&
            _calculateExpectedBPTToExit(balances, minAmountsOut) > collaterals[0].amount
        ) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("SlippageError()"))));
            service.close(0, data);
        } else {
            for (uint256 i = 0; i < loanLength; i++) {
                minAmountsOut[i] = GeneralMath.max(minAmountsOut[i], actualLoans[i].amount);
            }
            uint256 firstStep = _calculateExpectedBPTToExit(balances, minAmountsOut);
            if (firstStep > collaterals[0].amount) {
                // In this case we must annihilate minAmountsOut to obtain correct assertEq at the end
                firstStep = 0;
                minAmountsOut = new uint256[](loanLength);
            } else {
                for (uint256 i = 0; i < loanLength; i++) {
                    balances[i] -= minAmountsOut[i];
                }
            }
            uint256[] memory finalAmounts = _calculateExpectedTokensFromBPT(
                balances,
                collaterals[0].amount - firstStep,
                bptTotalSupply - firstStep
            );
            // TODO: this proves that most positions are badly liquidated: fix the strategy
            // TODO: Balancer quoter has a bug!!! redo it
            uint256 liquidationScore = service.liquidationScore(0);
            if (liquidationScore > 0) vm.prank(admin);
            service.close(0, data);
            // total supply as expected
            assertEq(IERC20(collateralTokens[0]).totalSupply(), bptTotalSupply - collaterals[0].amount);
            // min amounts out are respected
            for (uint256 i = 0; i < loanLength; i++) {
                // Service is emptied
                assertEq(IERC20(loanTokens[i]).balanceOf(address(service)), 0);
                // If firstStep = 0, minAmountsOut are also zero
                // Following line is to avoid stackTooDeep
                finalAmounts[i] += initialBalances[i] + minAmountsOut[i];
                // Payoff is paid to address(this) which is the user
                assertEq(
                    IERC20(loanTokens[i]).balanceOf(address(this)),
                    finalAmounts[i].positiveSub(actualLoans[i].amount)
                );
            }
        }
    }

    function testBalancerIntegrationQuoter(
        uint256 lusdLoan,
        uint256 lusdMargin,
        uint256 lqtyLoan,
        uint256 lqtyMargin,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        testBalancerIntegrationOpenPosition(lusdLoan, lusdMargin, lqtyLoan, lqtyMargin, wethLoan, wethMargin);
        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        uint256[] memory profits = service.quote(agreement); // TODO test quoter
    }
}
