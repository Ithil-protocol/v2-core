// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { GmxService } from "../../src/services/debit/GmxService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";

contract MockRouter {
    uint256 public amount;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    function handleRewards(bool, bool, bool, bool, bool, bool, bool) external {
        uint256 balance = weth.balanceOf(address(this));
        uint256 toTransfer = balance <= amount ? balance : amount;
        weth.transfer(msg.sender, toTransfer);
    }

    function setAmount(uint256 _amount) external {
        amount = _amount;
    }
}

contract ManualGmx is GmxService {
    constructor(
        address _manager,
        address _router,
        address _routerV2,
        uint256 _deadline
    ) GmxService(_manager, _router, _routerV2, _deadline) {}

    // adding total collateral is the only really free parameter, since the others are calculated after that
    function tweakState(uint128 collateral) external {
        if (collateral > 0) {
            totalCollateral += collateral;
            totalVirtualDeposits += (collateral * (totalRewards + totalVirtualDeposits)) / totalCollateral;
        }
    }

    // we can simulate the closure of a position with this, with a caveat:
    // we should be sure to leave at least the known positions' collaterals (otherwise it's inconsistent)
    // also, the mock router has a fixed reward which must change in a fuzzy way to increase test power
    function fakeClose(uint128 collateral, uint128 virtualDeposit) external {
        uint256 initialBalance = weth.balanceOf(address(this));
        router.handleRewards(false, false, false, false, false, true, false);
        // register rewards
        uint256 finalBalance = weth.balanceOf(address(this));
        uint256 newRewards = totalRewards + (finalBalance - initialBalance);
        // calculate share of rewards to give to the user
        uint256 totalWithdraw = ((newRewards + totalVirtualDeposits) * collateral) / totalCollateral;
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        // Due to integer arithmetic, we may get underflow if we do not make checks
        uint256 toTransfer = totalWithdraw >= virtualDeposit
            ? totalWithdraw - virtualDeposit <= finalBalance ? totalWithdraw - virtualDeposit : finalBalance
            : 0;
        // delete virtual deposits
        totalVirtualDeposits -= virtualDeposit;
        delete virtualDeposit;
        // update totalRewards and totalCollateral
        totalRewards = newRewards - toTransfer;
        totalCollateral -= collateral;
        // Transfer weth: since toTransfer <= totalWithdraw
        weth.transfer(msg.sender, toTransfer);
    }
}

contract GmxServiceTest is BaseIntegrationServiceTest {
    ManualGmx internal immutable service;

    address internal constant gmxRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address internal constant gmxRouterV2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address internal constant glpRewardTracker = 0xd2D1162512F927a7e282Ef43a362659E4F2a728F;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // USDC Native
    address internal constant whale = 0x0dF5dfd95966753f01cb80E76dc20EA958238C46;
    // USDC whale cannot be GMX itself, or it will break the contract!
    address internal constant usdcWhale = 0xE68Ee8A12c611fd043fB05d65E1548dC1383f2b9;
    uint256 internal constant amount = 1 * 1e20; // 100 WETH
    uint256 internal constant usdcAmount = 1e10; // 10k USDC

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    MockRouter internal mockRouter;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.deal(admin, 1 ether);
        vm.deal(whale, 1 ether);

        mockRouter = new MockRouter();
        vm.prank(admin);
        service = new ManualGmx(address(manager), address(mockRouter), gmxRouterV2, 30 * 86400);
    }

    function _equalityWithTolerance(uint256 amount1, uint256 amount2, uint256 tolerance) internal {
        assertGe(amount1 + tolerance, amount2);
        assertGe(amount2 + tolerance, amount1);
    }

    function setUp() public override {
        weth.approve(address(service), type(uint256).max);
        usdc.approve(address(service), type(uint256).max);

        vm.startPrank(whale);
        weth.transfer(admin, 1);
        weth.transfer(address(mockRouter), 1e18);
        vm.stopPrank();
        vm.prank(usdcWhale);
        usdc.transfer(admin, 1);
        vm.startPrank(admin);
        weth.approve(address(manager), 1);
        usdc.approve(address(manager), 1);
        manager.create(address(weth));
        manager.setCap(address(service), address(weth), GeneralMath.RESOLUTION, type(uint256).max);
        manager.create(address(usdc));
        manager.setCap(address(service), address(usdc), GeneralMath.RESOLUTION, type(uint256).max);
        service.setRiskParams(address(weth), 0, 0, 86400);
        service.setRiskParams(address(usdc), 0, 0, 86400);
        vm.stopPrank();

        vm.startPrank(whale);
        weth.transfer(address(this), 1e20);
        IVault vault = IVault(manager.vaults(address(weth)));
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(amount, whale);
        vm.stopPrank();

        vm.startPrank(usdcWhale);
        usdc.transfer(address(this), usdcAmount);
        IVault usdcVault = IVault(manager.vaults(address(usdc)));
        usdc.approve(address(usdcVault), type(uint256).max);
        usdcVault.deposit(usdcAmount, whale);
        vm.stopPrank();
    }

    function _openGmxEth(uint256 loanAmount, uint256 margin) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % 1e18;

        uint256[] memory margins = new uint256[](1);
        margins[0] = margin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0;

        IService.Order memory order = OrderHelper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );

        service.open(order);
    }

    function _openGmxUsdc(uint256 loanAmount, uint256 margin) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory loans = new uint256[](1);
        loans[0] = loanAmount % 1e9;

        uint256[] memory margins = new uint256[](1);
        margins[0] = margin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(0);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = ((loans[0] + margins[0]) * 99 * 1e12) / 100;

        IService.Order memory order = OrderHelper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );

        service.open(order);
    }

    function _generalOpenEth(
        uint256 loanAmount,
        uint256 margin,
        uint128 extraCollateral,
        uint256 index
    ) internal returns (uint128, uint128) {
        // test fuzzy to check opening a position is successful for any initial state
        uint256 initialCollateral = service.totalCollateral();
        uint256 initialVD = service.totalVirtualDeposits();
        margin = (margin % 9e17) + 1e17;
        service.tweakState(extraCollateral);
        _openGmxEth(loanAmount, margin);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(index);

        // state changes as expected
        assertEq(service.totalCollateral(), initialCollateral + extraCollateral + collaterals[0].amount);
        uint256 virtualDeposit = (collaterals[0].amount * (service.totalRewards() + initialVD)) /
            (initialCollateral + collaterals[0].amount);
        assertEq(service.totalVirtualDeposits(), initialVD + virtualDeposit);
        return (uint128(collaterals[0].amount), uint128(virtualDeposit));
    }

    function _generalOpenUsdc(
        uint256 loanAmount,
        uint256 margin,
        uint128 extraCollateral,
        uint256 index
    ) internal returns (uint128, uint128) {
        // test fuzzy to check opening a position is successful for any initial state
        uint256 initialCollateral = service.totalCollateral();
        uint256 initialVD = service.totalVirtualDeposits();
        margin = (margin % 9e7) + 1e8;
        service.tweakState(extraCollateral);
        _openGmxUsdc(loanAmount, margin);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(index);

        // state changes as expected
        assertEq(service.totalCollateral(), initialCollateral + extraCollateral + collaterals[0].amount);
        uint256 virtualDeposit = (collaterals[0].amount * (service.totalRewards() + initialVD)) /
            (initialCollateral + collaterals[0].amount);
        assertEq(service.totalVirtualDeposits(), initialVD + virtualDeposit);
        return (uint128(collaterals[0].amount), uint128(virtualDeposit));
    }

    function _modifyAmount(uint256 amount, uint256 seed) internal pure returns (uint128) {
        // A fairly crazy random number generator based on keccak256 and large primes
        uint256[8] memory bigPrimes;
        bigPrimes[0] = 2; // 2
        bigPrimes[1] = 3; // prime between 2^1 and 2^2
        bigPrimes[2] = 13; // prime between 2^2 and 2^4
        bigPrimes[3] = 251; // prime between 2^4 and 2^8
        bigPrimes[4] = 34591; // prime between 2^8 and 2^16
        bigPrimes[5] = 3883440697; // prime between 2^16 and 2^32
        bigPrimes[6] = 14585268654322704883; // prime between 2^32 and 2^64
        bigPrimes[7] = 5727913735782256336127425223006579443; // prime between 2^64 and 2^128
        // Since 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128 = 255 < 256 (or by direct calculation)
        // we can multiply all the bigPrimes without overflow
        // changing the primes (with the same constraints) would bring to an entirely different generator

        uint256 modifiedAmount = amount;
        for (uint256 i = 0; i < 8; i++) {
            uint256 multiplier = uint(keccak256(abi.encodePacked(modifiedAmount % bigPrimes[i], seed))) % bigPrimes[i];
            // Multiplier is fairly random but its logarithm is most likely near to 2^(2^i)
            // A total multiplication will therefore be near 2^255
            // To avoid this, we multiply with a probability of 50% at each round
            // We also need to avoid multiplying by zero, thus we add 1 at each factor
            if (multiplier % 2 != 0)
                modifiedAmount = (1 + (modifiedAmount % bigPrimes[i])) * (1 + (multiplier % bigPrimes[i]));
            // This number could be zero and can overflow, so we increment by one and take modulus at *every* iteration
            modifiedAmount = 1 + (modifiedAmount % bigPrimes[i]);
        }

        return uint128(modifiedAmount % (1 << 128));
    }

    function testGeneralCloseEth(
        uint256 loanAmount,
        uint256 margin,
        uint128 extraCollateral,
        uint128 fakeCollateral,
        uint128 virtualDeposit,
        uint128 reward,
        uint256 seed
    ) public {
        uint128[] memory collaterals = new uint128[](3);
        uint128[] memory virtualDeposits = new uint128[](3);
        // open three positions and modify state in a random way each time
        (collaterals[0], virtualDeposits[0]) = _generalOpenEth(loanAmount, margin, extraCollateral, 0);
        extraCollateral = _modifyAmount(extraCollateral, seed);
        (collaterals[1], virtualDeposits[1]) = _generalOpenEth(loanAmount, margin, extraCollateral, 1);
        extraCollateral = _modifyAmount(extraCollateral, seed);
        (collaterals[2], virtualDeposits[2]) = _generalOpenEth(loanAmount, margin, extraCollateral, 2);
        // close the three positions in a random order, always modifying the state
        service.tweakState(extraCollateral);
        fakeCollateral =
            fakeCollateral %
            uint128((service.totalCollateral() - collaterals[0] - collaterals[1] - collaterals[2] + 1) % (1 << 128));
        virtualDeposit =
            virtualDeposit %
            uint128(
                (service.totalVirtualDeposits() - virtualDeposits[0] - virtualDeposits[1] - virtualDeposits[2] + 1) %
                    (1 << 128)
            );
        service.fakeClose(fakeCollateral, virtualDeposit);
        mockRouter.setAmount(uint256(reward));
        uint256 index = seed % 3;
        service.close(index, abi.encode(1));
        index = (index + 1) % 3;
        service.close(index, abi.encode(1));
        index = (index + 1) % 3;
        service.close(index, abi.encode(1));
    }

    function testGeneralCloseUsdc(
        uint256 loanAmount,
        uint256 margin,
        uint128 extraCollateral,
        uint128 fakeCollateral,
        uint128 virtualDeposit,
        uint128 reward,
        uint256 seed
    ) public {
        uint128[] memory collaterals = new uint128[](3);
        uint128[] memory virtualDeposits = new uint128[](3);
        // open three positions and modify state in a random way each time
        (collaterals[0], virtualDeposits[0]) = _generalOpenUsdc(loanAmount, margin, extraCollateral, 0);
        extraCollateral = _modifyAmount(extraCollateral, seed);
        (collaterals[1], virtualDeposits[1]) = _generalOpenUsdc(loanAmount, margin, extraCollateral, 1);
        extraCollateral = _modifyAmount(extraCollateral, seed);
        (collaterals[2], virtualDeposits[2]) = _generalOpenUsdc(loanAmount, margin, extraCollateral, 2);
        // close the three positions in a random order, always modifying the state
        service.tweakState(extraCollateral);
        fakeCollateral =
            fakeCollateral %
            uint128((service.totalCollateral() - collaterals[0] - collaterals[1] - collaterals[2] + 1) % (1 << 128));
        virtualDeposit =
            virtualDeposit %
            uint128(
                (service.totalVirtualDeposits() - virtualDeposits[0] - virtualDeposits[1] - virtualDeposits[2] + 1) %
                    (1 << 128)
            );
        service.fakeClose(fakeCollateral, virtualDeposit);
        mockRouter.setAmount(uint256(reward));
        uint256 index = seed % 3;
        service.close(index, abi.encode(1));
        index = (index + 1) % 3;
        service.close(index, abi.encode(1));
        index = (index + 1) % 3;
        service.close(index, abi.encode(1));
    }
}
