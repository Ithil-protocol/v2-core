// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IPool } from "../../src/interfaces/external/wizardex/IPool.sol";
import { IFactory } from "../../src/interfaces/external/wizardex/IFactory.sol";
import { IOracle } from "../../src/interfaces/IOracle.sol";
import { Oracle } from "../../src/Oracle.sol";
import { MockChainLinkOracle } from "../helpers/MockChainLinkOracle.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { Ithil } from "../../src/Ithil.sol";
import { CallOption } from "../../src/services/credit/CallOption.sol";
import { FeeCollectorService } from "../../src/services/neutral/FeeCollectorService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";
import { GmxService } from "../../src/services/debit/GmxService.sol";

contract DebitCreditTest is Test, IERC721Receiver {
    // test in which we add Aave, feeCollector and call option
    // due to the complexity of the setup, fuzzy testing is limited
    // The states to be considered are three:
    // 1. Aave position open or not
    // 2. Call option open or not
    // 3. Fee collector deposit done or not

    using Math for uint256;
    // The owner of the manager and all services

    address internal immutable admin = address(uint160(uint256(keccak256(abi.encodePacked("admin")))));
    // who liquidates debit positions and also harvest fees (no need of two addresses)
    address internal immutable automator = address(uint160(uint256(keccak256(abi.encodePacked("automator")))));
    // vanilla depositor to the Vault
    address internal immutable liquidityProvider =
        address(uint160(uint256(keccak256(abi.encodePacked("liquidityProvider")))));
    // depositor of the call option: locks some capital and may exercise at maturity
    address internal immutable callOptionSigner =
        address(uint160(uint256(keccak256(abi.encodePacked("callOptionSigner")))));
    // user of Aave service: posts margin and takes loan
    address internal immutable aaveUser = address(uint160(uint256(keccak256(abi.encodePacked("aaveUser")))));
    // depositor of the fee collector service: wants to obtain fees from Ithil
    address internal immutable feeCollectorDepositor =
        address(uint160(uint256(keccak256(abi.encodePacked("feeCollectorDepositor")))));
    // another depositor should not be able to snatch fees from the first one
    address internal immutable feeCollectorDepositor2 =
        address(uint160(uint256(keccak256(abi.encodePacked("feeCollectorDepositor2")))));
    address internal immutable treasury = address(uint160(uint256(keccak256(abi.encodePacked("treasury")))));

    IManager internal immutable manager;

    AaveService internal immutable aaveService;
    CallOption internal immutable callOptionService;
    FeeCollectorService internal immutable feeCollectorService;
    Ithil internal immutable ithil;
    Oracle internal immutable oracle;

    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant wethWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address internal constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal constant usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address internal constant aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant aUsdc = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address internal constant dexFactory = 0xa05B704E88D43260F71861BB69C1851Fe77b63fD;
    address internal immutable usdcChainlinkFeed; /* = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3*/
    address internal immutable ethChainlinkFeed; /* = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612*/

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    uint64[] internal _rewards;

    constructor() {
        _rewards = new uint64[](12);
        _rewards[0] = 1059463094359295265;
        _rewards[1] = 1122462048309372981;
        _rewards[2] = 1189207115002721067;
        _rewards[3] = 1259921049894873165;
        _rewards[4] = 1334839854170034365;
        _rewards[5] = 1414213562373095049;
        _rewards[6] = 1498307076876681499;
        _rewards[7] = 1587401051968199475;
        _rewards[8] = 1681792830507429086;
        _rewards[9] = 1781797436280678609;
        _rewards[10] = 1887748625363386993;
        _rewards[11] = 2000000000000000000;
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);
        vm.startPrank(admin);
        // The true chainlink oracle will throw a stalePrice exception after warping
        // therefore we use mock oracle
        usdcChainlinkFeed = address(new MockChainLinkOracle(6));
        ethChainlinkFeed = address(new MockChainLinkOracle(18));
        usdcChainlinkFeed.call(abi.encodeWithSignature("setPrice(int256)", int256(1e6)));
        ethChainlinkFeed.call(abi.encodeWithSignature("setPrice(int256)", int256(1.8e18)));
        manager = IManager(new Manager());
        ithil = new Ithil(admin);
        oracle = new Oracle();
        aaveService = new AaveService(address(manager), aavePool, 30 * 86400);
        feeCollectorService = new FeeCollectorService(address(manager), weth, 1e17, address(oracle), dexFactory);
        // Create a vault for USDC
        // recall that the admin needs 1e-6 USDC to create the vault
        vm.stopPrank();
        vm.prank(usdcWhale);
        IERC20(usdc).transfer(address(admin), 1);

        vm.startPrank(admin);
        IERC20(usdc).approve(address(manager), 1);
        manager.create(usdc);

        // first price is 0.2 USDC: we need to double it in the constructor
        // because the smallest price can only be achieved by maximum lock time
        callOptionService = new CallOption(address(manager), address(ithil), 4e5, 86400 * 30, 86400 * 30, 0, usdc);
        vm.stopPrank();
    }

    function setUp() public {
        // ithil must be allocated to start the call option
        // we allocate 10 million Ithil
        vm.startPrank(admin);
        ithil.approve(address(callOptionService), 1e7 * 1e18);
        callOptionService.allocateIthil(1e7 * 1e18);
        callOptionService.transferOwnership(treasury);

        // whitelist user for Aave and Gmx
        address[] memory whitelistedUsers = new address[](1);
        whitelistedUsers[0] = aaveUser;
        aaveService.addToWhitelist(whitelistedUsers);

        // whitelist Aave strategy for 20% exposure in USDC
        manager.setCap(address(aaveService), address(usdc), 2e17, type(uint256).max);
        // we also need to whitelist call option and fee collector
        // since they generate no loan, even 1 is enough
        manager.setCap(address(feeCollectorService), address(usdc), 1, type(uint256).max);
        manager.setCap(address(callOptionService), address(usdc), 1, type(uint256).max);

        // give 1m Ithil to fee depositor
        ithil.transfer(feeCollectorDepositor, 1e6 * 1e18);
        // give 1m Ithil to second fee depositor
        ithil.transfer(feeCollectorDepositor2, 1e6 * 1e18);

        // set price feeds to the oracle (for fee collector)
        oracle.setPriceFeed(usdc, usdcChainlinkFeed);
        oracle.setPriceFeed(weth, ethChainlinkFeed);

        // support Ithil token as fee bearing (weigth 1.1)
        feeCollectorService.setTokenWeight(address(ithil), 1e18 + 1e17);

        vm.stopPrank();

        // give 100k USDC to everybody needing them
        vm.startPrank(usdcWhale);
        IERC20(usdc).transfer(liquidityProvider, 1e11);
        IERC20(usdc).transfer(callOptionSigner, 1e11);
        IERC20(usdc).transfer(aaveUser, 1e11);
        vm.stopPrank();

        // We also give 100 WETH to the automator which will be used to fulfill the dex order
        vm.startPrank(wethWhale);
        IERC20(weth).transfer(automator, 1e20);
        vm.stopPrank();
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _equalWithTolerance(uint256 a, uint256 b, uint256 tol) internal {
        assertGe(a + tol, b);
        assertGe(b + tol, a);
    }

    function _openAavePosition(uint256 margin, uint256 loan, uint256 minCollateral) internal {
        // Opens an Aave position in all cases (no check on interest)
        IService.Loan[] memory loans = new IService.Loan[](1);
        // we put a 10% interest rate
        loans[0] = IService.Loan(address(usdc), loan, margin, 1e17);
        IService.Collateral[] memory collaterals = new IService.Collateral[](1);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, aUsdc, 0, minCollateral);
        IService.Agreement memory agreement = IService.Agreement(
            loans,
            collaterals,
            block.timestamp,
            IService.Status.OPEN
        );
        IService.Order memory order = IService.Order(agreement, abi.encode(""));
        aaveService.open(order);
    }

    function _openCallOption(uint256 loan, uint256 monthsLocked) internal {
        IService.Loan[] memory loans = new IService.Loan[](1);
        loans[0] = IService.Loan(address(usdc), loan, 0, 1e18);
        IService.Collateral[] memory collaterals = new IService.Collateral[](2);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, manager.vaults(usdc), 0, 0);
        collaterals[1] = IService.Collateral(IService.ItemType.ERC20, address(ithil), 0, 0);
        IService.Agreement memory agreement = IService.Agreement(
            loans,
            collaterals,
            block.timestamp,
            IService.Status.OPEN
        );
        IService.Order memory order = IService.Order(agreement, abi.encode(monthsLocked));
        callOptionService.open(order);
    }

    function _openFeeCollectorPosition(uint256 margin, uint256 monthsLocked) internal {
        IService.Loan[] memory loans = new IService.Loan[](1);
        loans[0] = IService.Loan(address(ithil), 0, margin, 1e18);
        IService.Collateral[] memory collaterals = new IService.Collateral[](1); // uninitialized
        IService.Agreement memory agreement = IService.Agreement(
            loans,
            collaterals,
            block.timestamp,
            IService.Status.OPEN
        );
        IService.Order memory order = IService.Order(agreement, abi.encode(monthsLocked));
        feeCollectorService.open(order);
    }

    function testCallOption() public {
        // In this test, the user puts a call option in various states
        // notice that the call option does not need any former liquidity in the vault
        IVault vault = IVault(manager.vaults(usdc));
        vm.startPrank(callOptionSigner);
        uint256 depositedAmount = 4e9;
        uint256 monthsLocked = 1;
        IERC20(usdc).approve(address(callOptionService), depositedAmount);
        _openCallOption(depositedAmount, monthsLocked);
        vm.stopPrank();

        uint256 initialPrice = callOptionService.currentPrice();
        (, IService.Collateral[] memory collaterals, , ) = callOptionService.getAgreement(0);
        // no fees, thus deposited amount and collaterals[0] are the same (vault 1:1 with underlying)
        assertEq(collaterals[0].amount, depositedAmount);
        // due to the bump in the option price, we expect actual amount to be less than the virtual amount
        assertLe(collaterals[1].amount, (depositedAmount * _rewards[monthsLocked]) / initialPrice);
        // price was bumped by at least the allocation percentage (virtually) bougth
        assertGe(callOptionService.currentPrice(), initialPrice);
        assertEq(vault.freeLiquidity(), 4e9 + 1);
        // free liquidity = 4000 USDC

        // now depositedAmount are in the vault -> we take an Aave position
        // recall maximum amount is 20% at this point
        vm.startPrank(aaveUser);
        uint256 loan = 4e8;
        uint256 margin = 5e8;
        uint256 minCollateral = loan + margin;
        IERC20(usdc).approve(address(aaveService), margin);
        _openAavePosition(margin, loan, minCollateral);
        assertEq(vault.freeLiquidity(), 3.6e9 + 1);
        vm.stopPrank();
        // now, the free liquidity is 3600 USDC

        // with the position open, the option caller tries to close its position
        vm.startPrank(callOptionSigner);
        // lock period did not pass yet
        uint256 calledPortion = 0;
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("LockPeriodStillActive()"))));
        callOptionService.close(0, abi.encode(calledPortion));
        // we must warp the months locked
        vm.warp(block.timestamp + (monthsLocked + 1) * 30 * 86400);
        // since there is no sufficient liquidity, if the user withdraws we expect it to revert
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
        callOptionService.close(0, abi.encode(calledPortion));
        // if instead the caller exercises the option, even partially (more than 50%) no problem
        calledPortion = 9e17;
        uint256 initialCallerBalance = IERC20(usdc).balanceOf(callOptionSigner);
        callOptionService.close(0, abi.encode(calledPortion));
        // call option signer has expected ITHIL balance
        assertEq(ithil.balanceOf(callOptionSigner), (collaterals[1].amount * calledPortion) / 1e18);
        // call option signer has withdrawn the remaining part of assets
        assertEq(
            IERC20(usdc).balanceOf(callOptionSigner),
            initialCallerBalance + (depositedAmount * (1e18 - calledPortion)) / 1e18
        );
        // treasury has obtained the iToken used by the signer to obtain ITHIL
        assertEq(
            vault.balanceOf(treasury),
            collaterals[0].amount - vault.convertToShares(((depositedAmount * (1e18 - calledPortion)) / 1e18))
        );
        assertEq(vault.freeLiquidity(), depositedAmount - loan - (depositedAmount * (1e18 - calledPortion)) / 1e18 + 1);
        assertEq(vault.freeLiquidity(), 3.2e9 + 1);
        assertEq(vault.balanceOf(treasury), 3.6e9);
        vm.stopPrank();
        // The free liquidity is now 3200 USDC and treasury has 3600 USDC worth of iTokens

        // Now, another call option is signed and another Aave position is opened
        vm.startPrank(callOptionSigner);
        depositedAmount = 3e8;
        monthsLocked = 7;
        IERC20(usdc).approve(address(callOptionService), depositedAmount);
        _openCallOption(depositedAmount, monthsLocked);
        assertEq(vault.freeLiquidity(), 3.5e9 + 1);
        vm.stopPrank();
        // Now free liquidity is 3500 USDC, and 400 are taken as loan
        // Total assets are 3900 USDC, so we can still take 380 USDC as loan

        vm.startPrank(aaveUser);
        loan = 3.8e8;
        margin = 5e8;
        minCollateral = loan + margin;
        IERC20(usdc).approve(address(aaveService), margin);
        _openAavePosition(margin, loan, minCollateral);
        vm.stopPrank();
        // Now free liquidity is 3120 USDC

        // Now the treasury redeems its iTokens (taken from latest call option)
        vm.startPrank(treasury);
        // not all liquidity can be withdrawn, let us just redeem 2900 iUSDC
        vault.redeem(2.9e9, treasury, treasury);
        // Which makes the free liquidity to be 220 USDC
        assertEq(vault.freeLiquidity(), 2.2e8 + 1);
        vm.stopPrank();

        vm.startPrank(callOptionSigner);
        // lock period did not pass yet
        calledPortion = 0;
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("LockPeriodStillActive()"))));
        callOptionService.close(1, abi.encode(calledPortion));
        // we must warp the months locked
        vm.warp(block.timestamp + (monthsLocked + 1) * 30 * 86400);
        // since there is no sufficient liquidity, if the user withdraws we expect it to revert
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
        callOptionService.close(1, abi.encode(calledPortion));
        vm.stopPrank();

        // Before closing, we open a fee collector position
        // so that we can withdraw the fees later

        vm.startPrank(feeCollectorDepositor);
        // 100k Ithil locked for 6 months
        ithil.approve(address(feeCollectorService), 1e5 * 1e18);
        _openFeeCollectorPosition(1e5 * 1e18, 5);
        (, collaterals, , ) = feeCollectorService.getAgreement(0);
        assertEq(collaterals[0].amount, (1e5 * 1e18 * (_rewards[5] * uint256(1.1e18))) / 1e36);
        vm.stopPrank();

        // Now, liquidity is given by an Aave position which closes
        vm.startPrank(aaveUser);
        aaveService.close(0, abi.encode(0));
        // it used to be 400 USDC, so now we have them back
        assertEq(vault.freeLiquidity(), 6.2e8 + 1);
        vm.stopPrank();

        // At this point, fees are harvested
        vm.startPrank(automator);
        address[] memory tokens = new address[](1);
        tokens[0] = usdc;
        (uint256[] memory amounts, uint256[] memory prices) = feeCollectorService.harvestAndSwap(tokens);
        // the harvest is registered as a loss in the vault
        assertEq(vault.currentLosses(), amounts[0]);
        // This does not actually perform the swap: it justs places an order on the dex
        // Let the automator fulfill it
        IPool pool = IPool(IFactory(dexFactory).pools(usdc, weth, 5));
        IERC20(weth).approve(address(pool), type(uint256).max);
        pool.fulfillOrder(type(uint256).max, automator, amounts[0], type(uint256).max, block.timestamp + 3600);
        // the automator has successfully extracted the fees (more orders could be filled before the collector's)
        assertGe(IERC20(usdc).balanceOf(automator), amounts[0]);
        // and the resulting weth are introduced into the feeCollector contract
        assertEq(
            IERC20(weth).balanceOf(address(feeCollectorService)),
            amounts[0].mulDiv(1e18, prices[0], Math.Rounding.Up)
        );
        // if we try to harvest fees again, we would fail (we must wait for another repay)
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("Throttled()"))));
        feeCollectorService.harvestAndSwap(tokens);
        // we delay the fee collection to be able to test better when another fee collector tries to deposit
        vm.stopPrank();

        vm.startPrank(feeCollectorDepositor2);
        uint256 initialWithdrawable = feeCollectorService.withdrawable(0);
        // 100k Ithil locked for 8 months
        ithil.approve(address(feeCollectorService), 1e5 * 1e18);
        _openFeeCollectorPosition(1e5 * 1e18, 7);
        // new deposit does not affect withdrawable of the other user (beyond rounding error)
        _equalWithTolerance(feeCollectorService.withdrawable(0), initialWithdrawable, 1);
        (, collaterals, , ) = feeCollectorService.getAgreement(1);
        assertEq(collaterals[0].amount, (1e5 * 1e18 * (_rewards[7] * uint256(1.1e18))) / 1e36);

        // Although there are weth in the service, the new depositor can only withdraw 0
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedAccess()"))));
        feeCollectorService.withdrawFees(0);
        uint256 toWithdraw = feeCollectorService.withdrawFees(1);
        assertEq(toWithdraw, 0);
        vm.stopPrank();

        // let us now close the call option with all liquidity withdrawn
        vm.startPrank(callOptionSigner);
        callOptionService.close(1, abi.encode(0));
        vm.stopPrank();

        // and let us withdraw fees and close the position
        vm.startPrank(feeCollectorDepositor);
        initialWithdrawable = feeCollectorService.withdrawable(1);
        toWithdraw = feeCollectorService.withdrawFees(0);
        // withdraw fees does not affect withdrawable of the other user (beyond rounding error)
        _equalWithTolerance(feeCollectorService.withdrawable(1), initialWithdrawable, 1);
        assertEq(toWithdraw, amounts[0].mulDiv(1e18, prices[0], Math.Rounding.Down));
        assertEq(IERC20(weth).balanceOf(feeCollectorDepositor), toWithdraw);

        // launching again, immediately, withdrawFees should give a zero amount
        toWithdraw = feeCollectorService.withdrawFees(0);
        assertEq(toWithdraw, 0);

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("BeforeExpiry()"))));
        feeCollectorService.close(0, "");
        // recall it was six months
        vm.warp(block.timestamp + 6 * 30 * 86400);
        // and even more fees are introduced (mock transfer)
        vm.stopPrank();
        vm.prank(wethWhale);
        IERC20(weth).transfer(address(feeCollectorService), 1e18);
        initialWithdrawable = feeCollectorService.withdrawable(1);
        vm.prank(feeCollectorDepositor);
        feeCollectorService.close(0, "");
        // closing does not affect withdrawable of the other user (beyond rounding error)
        _equalWithTolerance(feeCollectorService.withdrawable(1), initialWithdrawable, 1);

        // now also the second depositor closes its position

        vm.startPrank(feeCollectorDepositor2);
        // two more months
        vm.warp(block.timestamp + 2 * 30 * 86400);
        feeCollectorService.close(1, "");
        vm.stopPrank();
    }
}
