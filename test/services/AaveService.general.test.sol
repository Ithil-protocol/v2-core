// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";

contract AaveGeneralTest is Test, IERC721Receiver {
    using GeneralMath for uint256;

    address internal immutable admin = address(uint160(uint256(keccak256(abi.encodePacked("admin")))));
    address internal immutable liquidator = address(uint160(uint256(keccak256(abi.encodePacked("liquidator")))));
    IManager internal immutable manager;

    AaveService internal immutable service;
    address internal constant aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address[] internal loanTokens;
    mapping(address => address) internal whales;
    address[] internal collateralTokens;
    uint256 internal loanLength;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        whales[loanTokens[0]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        collateralTokens[0] = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);
        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new AaveService(address(manager), aavePool, 30 * 86400);
        service.setLiquidator(liquidator);
        vm.stopPrank();
    }

    function setUp() public virtual {
        for (uint256 i = 0; i < loanLength; i++) {
            IERC20(loanTokens[i]).approve(address(service), type(uint256).max);

            vm.deal(whales[loanTokens[i]], 1 ether);
        }
        for (uint256 i = 0; i < loanLength; i++) {
            // Create Vault: DAI
            vm.prank(whales[loanTokens[i]]);
            IERC20(loanTokens[i]).transfer(admin, 1);
            vm.startPrank(admin);
            IERC20(loanTokens[i]).approve(address(manager), 1);
            manager.create(loanTokens[i]);
            // No caps for this service -> 100% of the liquidity can be used initially
            manager.setCap(address(service), loanTokens[i], GeneralMath.RESOLUTION, type(uint256).max);
            // Set risk spread at 0.5%, 1% base rate, halving time one month
            service.setRiskParams(loanTokens[0], 5e15, 1e16, 365 * 30);
            service.setMinMargin(loanTokens[0], 1e6); // Minimum 1 DAI
            vm.stopPrank();
        }
        vm.prank(admin);
        (bool success, ) = address(service).call(abi.encodeWithSignature("toggleWhitelistFlag()"));
        require(success, "toggleWhitelistFlag failed");
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _prepareVaultAndUser(
        uint256 vaultAmount,
        uint256 loan,
        uint256 margin
    ) internal returns (uint256, uint256) {
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        if (whaleBalance == 0) return (0, 0);
        // if we are here, whaleBalance > 0
        vaultAmount = vaultAmount % whaleBalance;
        if (vaultAmount == 0) vaultAmount++;
        vm.startPrank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).approve(address(manager.vaults(loanTokens[0])), vaultAmount);
        IVault(manager.vaults(loanTokens[0])).deposit(vaultAmount, whales[loanTokens[0]]);
        vm.stopPrank();

        whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        margin = (((margin % whaleBalance) % 1e12) + 1e6).min(whaleBalance); // Max 1m, min 1
        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(address(this), margin);
        loan = (loan % vaultAmount) % 1e12; // Max 1m
        (, uint256 currentBase) = service.latestAndBase(loanTokens[0]).unpackUint();
        loan = loan.min((GeneralMath.RESOLUTION * margin) / (currentBase + 5e15));
        return (loan, margin);
    }

    function _prepareOrder(uint256 loan, uint256 margin) internal returns (IService.Order memory) {
        IService.Order memory order;
        {
            IService.Loan[] memory loans = new IService.Loan[](loanLength);
            IService.Collateral[] memory collaterals = new IService.Collateral[](loanLength);
            uint256 freeLiquidity = IVault(manager.vaults(loanTokens[0])).freeLiquidity();
            // Loan cannot be more than a certain amount or it causes an InterestRateOverflow()
            (, uint256 currentBase) = service.latestAndBase(loanTokens[0]).unpackUint();
            uint256 maxLoan = freeLiquidity.safeMulDiv(GeneralMath.RESOLUTION - currentBase, GeneralMath.RESOLUTION);
            loan = maxLoan == 0 ? 0 : loan % maxLoan;
            (uint256 baseRate, uint256 spread) = service.computeBaseRateAndSpread(
                loanTokens[0],
                loan,
                margin,
                freeLiquidity
            );
            loans[0] = IService.Loan(loanTokens[0], loan, margin, GeneralMath.packInUint(baseRate, spread));
            collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, 1);
            order = IService.Order(
                IService.Agreement(
                    loans,
                    collaterals,
                    0, // useless: the code updates it at the moment of saving
                    IService.Status.OPEN // also useless
                ),
                abi.encode("")
            );
        }
        return order;
    }

    function _openOrder(uint256 vaultAmount, uint256 loan, uint256 margin, uint64 warp) internal {
        warp = warp % (365 * 86400); // Warp 1y maximum
        (loan, margin) = _prepareVaultAndUser(vaultAmount, loan, margin);
        IService.Order memory order = _prepareOrder(loan, margin);
        // No need to check invariants: they are already checked in other tests
        if (order.agreement.loans[0].margin < 1e6) return;
        service.open(order);
        vm.warp(block.timestamp + warp);
    }

    function _getInterestAndSpread(uint256 tokenID) internal returns (uint256, uint256) {
        (IService.Loan[] memory actualLoans, , , ) = service.getAgreement(tokenID);
        uint256 interestAndSpread = actualLoans[0].interestAndSpread;
        return (interestAndSpread >> 128, interestAndSpread % (1 << 128));
    }

    function _closeAgreement(uint256 index, uint256 minimumAmountOut) internal {
        uint256 totalIds = service.id();
        index = totalIds == 0 ? 0 : index % totalIds;
        if (index == 0) return;
        (
            IService.Loan[] memory actualLoans,
            IService.Collateral[] memory actualCollaterals,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(index);
        IService.Agreement memory agreement = IService.Agreement(actualLoans, actualCollaterals, createdAt, status);
        if (status != IService.Status.OPEN) {
            vm.expectRevert();
            service.close(index, abi.encode(minimumAmountOut));
        } else {
            if (minimumAmountOut > service.quote(agreement)[0]) {
                vm.expectRevert();
                service.close(index, abi.encode(minimumAmountOut));
            } else {
                uint256 initialVaultBalance = IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0]));
                uint256 initialUserBalance = IERC20(loanTokens[0]).balanceOf(address(this));
                uint256[] memory dueFees = service.computeDueFees(agreement);
                uint256[] memory quoted = service.quote(agreement);
                if (quoted[0] < actualLoans[0].amount) {
                    vm.expectRevert(bytes4(keccak256(abi.encodePacked("LossByArbitraryAddress()"))));
                    service.close(index, abi.encode(minimumAmountOut));
                } else {
                    uint256[] memory obtained = service.close(index, abi.encode(minimumAmountOut));
                    if (obtained[0] > actualLoans[0].amount + dueFees[0]) {
                        // Good repay
                        assertEq(
                            IERC20(loanTokens[0]).balanceOf(address(this)),
                            initialUserBalance + obtained[0] - (actualLoans[0].amount + dueFees[0])
                        );
                        assertEq(
                            IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0])),
                            initialVaultBalance + actualLoans[0].amount + dueFees[0]
                        );
                    } else {
                        // Bad repay
                        assertEq(IERC20(loanTokens[0]).balanceOf(address(this)), initialUserBalance);
                        assertEq(
                            IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0])),
                            initialVaultBalance + obtained[0]
                        );
                    }
                }
            }
        }
    }

    function _modifyBalance(uint256 modify, uint256 giveOrTake) internal {
        if (giveOrTake % 2 == 0) {
            // Give aTokens to the service
            uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
            modify = whaleBalance == 0 ? 0 : modify % whaleBalance;
            modify %= 1e13; // Max 10m
            vm.startPrank(whales[loanTokens[0]]);
            IERC20(loanTokens[0]).approve(aavePool, modify);
            (bool success, ) = aavePool.call(
                abi.encodeWithSignature(
                    "supply(address,uint256,address,uint16)",
                    loanTokens[0],
                    modify,
                    whales[loanTokens[0]],
                    0
                )
            );
            require(success || modify == 0, "Supply failed");
            IERC20(collateralTokens[0]).transfer(
                address(service),
                IERC20(collateralTokens[0]).balanceOf(whales[loanTokens[0]])
            );
            vm.stopPrank();
        } else {
            // Snatch tokens from the service
            uint256 serviceBalance = IERC20(collateralTokens[0]).balanceOf(address(service));
            modify = serviceBalance == 0 ? 0 : modify % serviceBalance;
            vm.prank(address(service));
            IERC20(collateralTokens[0]).transfer(whales[loanTokens[0]], modify);
        }
    }

    function _randomTest(
        uint256 vaultAmount,
        uint256 loan,
        uint256 margin,
        uint64 warp,
        uint256 index,
        uint256 minimumAmountOut,
        uint256 modify,
        uint256 giveOrTake,
        uint256 seed
    ) internal {
        if (seed % 3 == 0) _openOrder(vaultAmount, loan, margin, warp);
        if (seed % 3 == 1) _closeAgreement(index, minimumAmountOut);
        if (seed % 3 == 2) _modifyBalance(modify, giveOrTake);
    }

    function testInterestRateChange(uint256 vaultAmount, uint256 loan, uint256 margin, uint64 warp) public {
        _openOrder(vaultAmount, loan, margin, warp);
        (uint256 interest1, ) = _getInterestAndSpread(0);
        // Open a new order: time is already warped by "warp" after first one
        _openOrder(vaultAmount, loan, margin, 0);
        // there is a chance that latest order was not open due to margin constraint
        // I add this check to avoid index out of bounds
        if (service.id() > 1) {
            (uint256 interest2, ) = _getInterestAndSpread(1);
            uint256 rateDecay = warp < 2 * service.halvingTime(loanTokens[0])
                ? (interest1 * (2 * service.halvingTime(loanTokens[0]) - warp)) /
                    (2 * service.halvingTime(loanTokens[0]))
                : 0;
            assertGe(interest2, rateDecay);
        }
    }

    function testRandom(
        uint256 vaultAmount,
        uint256 loan,
        uint256 margin,
        uint64 warp,
        uint256 index,
        uint256 minimumAmountOut,
        uint256 modify,
        uint256 giveOrTake,
        uint256 seed
    ) internal {
        _randomTest(vaultAmount, loan, margin, warp, index, minimumAmountOut, modify, giveOrTake, seed);
        seed %= 5727913735782256336127425223006579443;
        _randomTest(vaultAmount, loan, margin, warp, index, minimumAmountOut, modify, giveOrTake, seed);
        seed %= 14585268654322704883;
        _randomTest(vaultAmount, loan, margin, warp, index, minimumAmountOut, modify, giveOrTake, seed);
        seed %= 3883440697;
        _randomTest(vaultAmount, loan, margin, warp, index, minimumAmountOut, modify, giveOrTake, seed);
        seed %= 38834;
        _randomTest(vaultAmount, loan, margin, warp, index, minimumAmountOut, modify, giveOrTake, seed);
    }
}
