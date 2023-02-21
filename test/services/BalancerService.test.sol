// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IBalancerVault } from "../../src/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerPool } from "../../src/interfaces/external/balancer/IBalancerPool.sol";
import { BalancerService } from "../../src/services/debit/BalancerService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { WeightedMath } from "../../src/libraries/external/Balancer/WeightedMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";
import { console2 } from "forge-std/console2.sol";

/// @dev See the "Writing Tests" section in the Foundry Book if this is your first time with Forge.
/// @dev Run Forge with `-vvvv` to see console logs.
/// https://book.getfoundry.sh/forge/writing-tests

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

/*
contract BalancerServiceWeightedDAIWETH is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    BalancerService internal immutable service;
    address internal constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // address internal constant auraBooster = 0x7818A1DA7BD1E64c199029E86Ba244a9798eEE10;

    bytes32 internal balancerPoolID = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    address internal gauge = 0x4ca6AC0509E6381Ca7CD872a6cdC0Fbf00600Fa1;
    address internal bal = 0xba100000625a3754423978a60c9317c58a424e3D;

    // address internal constant auraPoolID = 2;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new BalancerService(address(manager), balancerVault, bal);
        vm.stopPrank();
        loanLength = 2;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        loanTokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
        whales[loanTokens[0]] = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        whales[loanTokens[1]] = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
        collateralTokens[0] = 0x0b09deA16768f0799065C475bE02919503cB2a35; // Pool 60 WETH - 40 DAI
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(collateralTokens[0], balancerPoolID, gauge);
    }

    function _calculateExpectedTokens(uint256 amount0, uint256 amount1) internal view {

        (, uint256[] memory balances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
        uint256[] memory amountsIn = new uint256[](loanLength);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;
        uint256 maxWeightTokenIndex;
        for(uint256 i = 0; i < loanLength; i++) {
            if(normalizedWeights[i] > normalizedWeights[maxWeightTokenIndex])
                maxWeightTokenIndex = i;
        }    
        uint256[] memory dueProtocolFeeAmounts = new uint256[](loanLength);
        
        dueProtocolFeeAmounts[maxWeightTokenIndex] = WeightedMath._calcDueTokenProtocolSwapFeeAmount(
            balances[maxWeightTokenIndex],
            normalizedWeights[maxWeightTokenIndex],
            previousInvariant,
            currentInvariant,
            protocolSwapFeePercentage
        );
        uint256 bptAmountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            normalizedWeights,
            amountsIn,
            IERC20(collateralTokens[0]).totalSupply(),
            IBalancerPool(collateralTokens[0]).getSwapFeePercentage()
        );
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
        
        service.open(order);

        (
            ,
            IService.Collateral[] memory collaterals,
            ,
            
        ) = service.getAgreement(1);
        console2.log("bptAmountOut", bptAmountOut);
        console2.log("collaterals[0].amount", collaterals[0].amount);
        assertTrue(collaterals[0].amount == bptAmountOut);
    }

    function testClose(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1,
        uint256 minAmountsOutDai,
        uint256 minAmountsOutUsdc
    ) public {
        (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        vm.assume(minAmountsOutDai <= totalBalances[0]);
        vm.assume(minAmountsOutUsdc <= totalBalances[1]);

        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);

        uint256[] memory minAmountsOut = new uint256[](2);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = minAmountsOutDai;
        minAmountsOut[1] = minAmountsOutUsdc;
        bytes memory data = abi.encode(minAmountsOut);

        (IService.Loan[] memory loans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        bool slippageEnforced = minAmountsOutDai > loans[0].amount && minAmountsOutUsdc > loans[1].amount;
        if (slippageEnforced) {
            uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
            (, totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
            uint256 swapFee = IBalancerPool(collateralTokens[0]).getSwapFeePercentage();
            uint256 bptTotalSupply = IERC20(collateralTokens[0]).totalSupply();
            uint256 bptAmountOut = WeightedMath._calcBptInGivenExactTokensOut(
                totalBalances,
                normalizedWeights,
                minAmountsOut,
                bptTotalSupply,
                swapFee
            );
            if (bptAmountOut > collaterals[0].amount) {
                // This case is when slippage is exceeded
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("SlippageError()"))));
                service.close(0, data);
            } else {
                uint256 initialDaiBalance = IERC20(loanTokens[0]).balanceOf(address(service));
                uint256 initialWethBalance = IERC20(loanTokens[1]).balanceOf(address(service));
                service.close(0, data);
                // collateral tokens have been burned
                assertTrue(IERC20(collateralTokens[0]).totalSupply() == bptTotalSupply - collaterals[0].amount);
                // min amounts out are respected
                assertTrue(IERC20(loanTokens[0]).balanceOf(address(service)) >= initialDaiBalance + minAmountsOut[0]);
                assertTrue(IERC20(loanTokens[1]).balanceOf(address(service)) >= initialWethBalance + minAmountsOut[1]);
            }
        } else {
            service.close(0, data);
        }
    }

    function testQuote(uint256 amount0, uint256 loan0, uint256 margin0, uint256 amount1, uint256 loan1, uint256 margin1)
        public
    {
        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);
        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        (uint256[] memory profits, ) = service.quote(agreement);
    }

    // testAddPool() public {

    // }

    // testRemovePool() public {

    // }
}

contract BalancerServiceWeightedOHMWETH is BalancerServiceWeightedDAIWETH {
    using GeneralMath for uint256;

    // address internal constant auraPoolID = 2;

    function setUp() public override {
        loanTokens[0] = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5; // ohm
        loanTokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
        whales[loanTokens[0]] = 0x64C0fe73Dff66a8b9b803A1796082a575899DD26;
        whales[loanTokens[1]] = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
        collateralTokens[0] = 0xD1eC5e215E8148D76F4460e4097FD3d5ae0A3558; // Pool 50 OHM - 50 WETH
        balancerPoolID = 0xd1ec5e215e8148d76f4460e4097fd3d5ae0a35580002000000000000000003d3;
        gauge = address(0);
        super.setUp();
    }
}
*/

contract BalancerServiceWeightedTriPool is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    BalancerService internal immutable service;

    address internal constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal constant balancerPoolID = 0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002;
    address internal constant gauge = 0x104f1459a2fFEa528121759B238BB609034C2f01;
    address internal constant bal = 0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8;
    address internal constant gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    // address internal constant weightedMath = 0x37aaA5c2925b6A30D76a3D4b6C7D2a9137F02dc2;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 58581858;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new BalancerService(address(manager), balancerVault, bal);
        vm.stopPrank();
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
        uint256[] memory scaledArray = new uint256[](loanLength);
        for (uint256 i = 0; i < loanLength; i++) {
            // Tokens with more than 18 decimals are not supported.
            uint256 decimalsDifference = 18 - IERC20Metadata(address(loanTokens[i])).decimals();
            array[i] *= 10**decimalsDifference;
        }
    }

    function _calculateExpectedTokens(uint256 amount0, uint256 amount1, uint256 amount2)
        internal
        view
        returns (uint256)
    {
        (, uint256[] memory balances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
        uint256[] memory amountsIn = new uint256[](loanLength);
        amountsIn[0] = amount0;
        amountsIn[1] = amount1;
        amountsIn[2] = amount2;
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
        _upscaleArray(amountsIn);
        return
            WeightedMath._calcBptOutGivenExactTokensIn(
                balances,
                normalizedWeights,
                amountsIn,
                IERC20(collateralTokens[0]).totalSupply(),
                IBalancerPool(collateralTokens[0]).getSwapFeePercentage()
            );
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
        uint256 expectedTokens = _calculateExpectedTokens(
            order.agreement.loans[0].amount + order.agreement.loans[0].margin,
            order.agreement.loans[1].amount + order.agreement.loans[1].margin,
            order.agreement.loans[2].amount + order.agreement.loans[2].margin
        );
        (, uint256[] memory balances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        service.open(order);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        assertEq(collaterals[0].amount, expectedTokens);
    }

    function testBalancerIntegrationClosePosition(
        uint256 loan0,
        uint256 margin0,
        uint256 loan1,
        uint256 margin1,
        uint256 loan2,
        uint256 margin2,
        uint256 minAmountsOutWbtc,
        uint256 minAmountsOutWeth,
        uint256 minAmountsOutUsdc
    ) public {
        (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        vm.assume(minAmountsOutWbtc <= totalBalances[0]);
        vm.assume(minAmountsOutWeth <= totalBalances[1]);
        vm.assume(minAmountsOutUsdc <= totalBalances[2]);

        testBalancerIntegrationOpenPosition(loan0, margin0, loan1, margin1, loan2, margin2);

        uint256[] memory minAmountsOut = new uint256[](3);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = minAmountsOutWbtc;
        minAmountsOut[1] = minAmountsOutWeth;
        minAmountsOut[2] = minAmountsOutUsdc;
        bytes memory data = abi.encode(minAmountsOut);

        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        bool slippageEnforced = minAmountsOutWbtc > actualLoans[0].amount &&
            minAmountsOutWeth > actualLoans[1].amount &&
            minAmountsOutUsdc > actualLoans[2].amount;
        if (slippageEnforced) {
            uint256[] memory normalizedWeights = IBalancerPool(collateralTokens[0]).getNormalizedWeights();
            (, totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
            uint256 swapFee = IBalancerPool(collateralTokens[0]).getSwapFeePercentage();
            uint256 bptTotalSupply = IERC20(collateralTokens[0]).totalSupply();
            uint256 bptAmountOut = WeightedMath._calcBptInGivenExactTokensOut(
                totalBalances,
                normalizedWeights,
                minAmountsOut,
                bptTotalSupply,
                swapFee
            );
            if (bptAmountOut > collaterals[0].amount) {
                // This case is when slippage is exceeded
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("SlippageError()"))));
                service.close(0, data);
            } else {
                uint256 initiallusdBalance = IERC20(loanTokens[0]).balanceOf(address(service));
                uint256 initiallqtyBalance = IERC20(loanTokens[1]).balanceOf(address(service));
                uint256 initialWethBalance = IERC20(loanTokens[2]).balanceOf(address(service));
                service.close(0, data);
                // collateral tokens have been burned
                assertTrue(IERC20(collateralTokens[0]).totalSupply() == bptTotalSupply - collaterals[0].amount);
                // min amounts out are respected
                assertTrue(IERC20(loanTokens[0]).balanceOf(address(service)) >= initiallusdBalance + minAmountsOut[0]);
                assertTrue(IERC20(loanTokens[1]).balanceOf(address(service)) >= initiallqtyBalance + minAmountsOut[1]);
                assertTrue(IERC20(loanTokens[2]).balanceOf(address(service)) >= initialWethBalance + minAmountsOut[2]);
            }
        } else {
            service.close(0, data);
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
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        (uint256[] memory profits, ) = service.quote(agreement);
    }

    // testAddPool() public {

    // }

    // testRemovePool() public {

    // }
}
