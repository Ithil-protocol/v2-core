// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    }

    function testClose(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1,
        uint256 minAmountsOutDai,
        uint256 minAmountsOutWeth
    ) public {
        (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        vm.assume(minAmountsOutDai <= totalBalances[0]);
        vm.assume(minAmountsOutWeth <= totalBalances[1]);

        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);

        uint256[] memory minAmountsOut = new uint256[](2);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = minAmountsOutDai;
        minAmountsOut[1] = minAmountsOutWeth;
        bytes memory data = abi.encode(minAmountsOut);

        (IService.Loan[] memory loans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        bool slippageEnforced = minAmountsOutDai > loans[0].amount && minAmountsOutWeth > loans[1].amount;
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

        service.quote(agreement);
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

contract BalancerServiceWeightedLUSDLQTYWETH is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    BalancerService internal immutable service;

    address internal constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal constant balancerPoolID = 0x5512a4bbe7b3051f92324bacf25c02b9000c4a500001000000000000000003d7;
    address internal constant gauge = address(0);
    address internal constant bal = 0xba100000625a3754423978a60c9317c58a424e3D;

    // address internal constant weightedMath = 0x37aaA5c2925b6A30D76a3D4b6C7D2a9137F02dc2;

    // address internal constant auraPoolID = 2;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new BalancerService(address(manager), balancerVault, bal);
        vm.stopPrank();
        loanLength = 3;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // lusd
        loanTokens[1] = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D; // lqty
        loanTokens[2] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
        whales[loanTokens[0]] = 0x954f2a8b86Aa586c3Cc3a2088B72e2a560D7Dc22;
        whales[loanTokens[1]] = 0x954f2a8b86Aa586c3Cc3a2088B72e2a560D7Dc22;
        whales[loanTokens[2]] = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
        collateralTokens[0] = 0x5512A4bbe7B3051f92324bAcF25C02b9000c4a50; // Pool 33 LUSD - 33 LQTY - 33 WETH
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(collateralTokens[0], balancerPoolID, gauge);
    }

    function testOpen(uint256 loan0, uint256 margin0, uint256 loan1, uint256 margin1, uint256 loan2, uint256 margin2)
        public
    {
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
        service.open(order);
    }

    function testClose(
        uint256 loan0,
        uint256 margin0,
        uint256 loan1,
        uint256 margin1,
        uint256 loan2,
        uint256 margin2,
        uint256 minAmountsOutlusd,
        uint256 minAmountsOutlqty,
        uint256 minAmountsOutWeth
    ) public {
        (, uint256[] memory totalBalances, ) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolID);
        // WARNING: this is necessary otherwise Balancer math library throws a SUB_OVERFLOW error
        vm.assume(minAmountsOutlusd <= totalBalances[0]);
        vm.assume(minAmountsOutlqty <= totalBalances[1]);
        vm.assume(minAmountsOutWeth <= totalBalances[2]);

        testOpen(loan0, margin0, loan1, margin1, loan2, margin2);

        uint256[] memory minAmountsOut = new uint256[](3);
        // Fees make the initial investment always at a loss
        // In this test we allow any loss: quoter tests will make this more precise
        minAmountsOut[0] = minAmountsOutlusd;
        minAmountsOut[1] = minAmountsOutlqty;
        minAmountsOut[2] = minAmountsOutWeth;
        bytes memory data = abi.encode(minAmountsOut);

        (IService.Loan[] memory actualLoans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        bool slippageEnforced = minAmountsOutlusd > actualLoans[0].amount &&
            minAmountsOutlqty > actualLoans[1].amount &&
            minAmountsOutWeth > actualLoans[2].amount;
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

    function testQuote(
        uint256 lusdLoan,
        uint256 lusdMargin,
        uint256 lqtyLoan,
        uint256 lqtyMargin,
        uint256 wethLoan,
        uint256 wethMargin
    ) public {
        testOpen(lusdLoan, lusdMargin, lqtyLoan, lqtyMargin, wethLoan, wethMargin);
        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        service.quote(agreement);
    }

    // testAddPool() public {

    // }

    // testRemovePool() public {

    // }
}
