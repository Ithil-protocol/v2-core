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

contract AaveEconomicTest is Test, IERC721Receiver {
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

    function _aaveSupply(address token, uint256 amount, address onBehalfOf) internal {
        (bool success, ) = aavePool.call(
            abi.encodeWithSignature("supply(address,uint256,address,uint16)", token, amount, onBehalfOf, 0)
        );
        require(success, "Aave supply failed");
    }

    function _aaveBorrow(address token, uint256 amount, uint256 interestRateMode, address onBehalfOf) internal {
        (bool success, ) = aavePool.call(
            abi.encodeWithSignature(
                "borrow(address,uint256,uint256,uint16,address)",
                token,
                amount,
                interestRateMode,
                0,
                onBehalfOf
            )
        );
        require(success, "Aave borrow failed");
    }

    function _equalityWithTolerance(uint256 amount1, uint256 amount2, uint256 tolerance) internal {
        assertGe(amount1 + tolerance, amount2);
        assertGe(amount2 + tolerance, amount1);
    }

    function _prepareVaultAndUser(
        uint256 vaultAmount,
        uint256 loan,
        uint256 margin,
        uint64 warp
    ) internal returns (uint256, uint256, uint256, uint64) {
        warp = warp % (365 * 86400 * 10); // Warp 10y maximum
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        vaultAmount = whaleBalance == 0 ? 0 : vaultAmount % whaleBalance;
        if (vaultAmount == 0) vaultAmount++;
        vm.startPrank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).approve(address(manager.vaults(loanTokens[0])), vaultAmount);
        IVault(manager.vaults(loanTokens[0])).deposit(vaultAmount, whales[loanTokens[0]]);
        vm.stopPrank();

        whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        margin = (margin % whaleBalance) % 1e13; // Max 10m
        if (margin == 0) margin++;
        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(address(this), margin);
        loan = (loan % vaultAmount) % 1e13; // Max 10m

        return (vaultAmount, loan, margin, warp);
    }

    function testAaveSupplyBorrow(uint256 vaultAmount, uint256 loan, uint256 margin, uint64 warp) public {
        (vaultAmount, loan, margin, warp) = _prepareVaultAndUser(vaultAmount, loan, margin, warp);

        IService.Order memory order;
        {
            IService.Loan[] memory loans = new IService.Loan[](loanLength);
            IService.Collateral[] memory collaterals = new IService.Collateral[](loanLength);
            uint256 freeLiquidity = IVault(manager.vaults(loanTokens[0])).freeLiquidity();
            // Loan cannot be more than a certain amount or it causes an InterestRateOverflow()
            (, uint256 currentBase) = service.latestAndBase(loanTokens[0]).unpackUint();
            uint256 maxLoan = (freeLiquidity * (GeneralMath.RESOLUTION - currentBase - 5e15)) / GeneralMath.RESOLUTION;
            maxLoan = maxLoan.min((GeneralMath.RESOLUTION * margin) / (currentBase + 5e15));
            loan = maxLoan == 0 ? 0 : loan % maxLoan;
            (uint256 baseRate, uint256 spread) = service.computeBaseRateAndSpread(
                loanTokens[0],
                loan,
                margin,
                freeLiquidity
            );
            loans[0] = IService.Loan(loanTokens[0], loan, margin, GeneralMath.packInUint(baseRate, spread));
            collaterals[0] = IService.Collateral(
                IService.ItemType.ERC20,
                collateralTokens[0],
                0,
                loan + margin < 2 ? loan + margin : loan + margin - 1
            );
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
        uint256 initialUserAmount = IERC20(loanTokens[0]).balanceOf(address(this));
        uint256 initialVaultBalance = IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0]));
        service.open(order);
        (
            IService.Loan[] memory actualLoans,
            IService.Collateral[] memory actualCollaterals,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(0);

        IService.Agreement memory agreement = IService.Agreement(actualLoans, actualCollaterals, createdAt, status);

        uint256 supplyAmount = (IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]) / 2) % 1e13; // Max 10m
        if (supplyAmount > 0) {
            vm.startPrank(whales[loanTokens[0]]);
            IERC20(loanTokens[0]).approve(aavePool, supplyAmount);
            _aaveSupply(loanTokens[0], supplyAmount, whales[loanTokens[0]]);
            // After borrowing, fees are generated
            _aaveBorrow(weth, supplyAmount / 4000, 2, whales[loanTokens[0]]);
            vm.warp(block.timestamp + warp);
            vm.stopPrank();
        }

        bytes memory data = abi.encode(0);
        uint256 finalCollateral = IERC20(collateralTokens[0]).balanceOf(address(service));
        assertGe(finalCollateral, actualCollaterals[0].amount);
        uint256[] memory dueFees = service.computeDueFees(agreement);
        // Of course, it is impossible to give back to the vault more than the final collateral
        uint256 toGiveToVault = (actualLoans[0].amount + dueFees[0]).min(finalCollateral);
        if (service.liquidationScore(0) == 0 && createdAt + service.deadline() > block.timestamp) {
            vm.startPrank(liquidator);
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("RestrictedToOwner()"))));
            service.close(0, data);
            vm.stopPrank();
            service.close(0, data);
        } else {
            service.close(0, data);
        }
        assertEq(
            IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0])),
            initialVaultBalance + toGiveToVault - actualLoans[0].amount
        );
        // Due to Aave Ray Math approximations, a tolerance of 1 is necessary
        // It would be exact if instead of finalCollateral we put the actual, loan token amount obtained by closing
        _equalityWithTolerance(
            IERC20(loanTokens[0]).balanceOf(address(this)),
            initialUserAmount - actualLoans[0].margin + finalCollateral.positiveSub(toGiveToVault),
            1
        );
    }
}
