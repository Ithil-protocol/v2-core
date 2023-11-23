// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { Ithil } from "../../src/Ithil.sol";
import { CallOption } from "../../src/services/credit/CallOption.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract CallOptionTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    CallOption internal immutable service;
    Ithil internal immutable ithil;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    uint64[] internal _rewards;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
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
        vm.startPrank(admin);
        ithil = new Ithil(admin);
        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](2);
        loanTokens[0] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        whales[loanTokens[0]] = 0x252cd7185dB7C3689a571096D5B57D45681aA080;
        vm.stopPrank();

        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(admin, 1);

        vm.startPrank(admin);
        IERC20(loanTokens[0]).approve(address(manager), 1);
        manager.create(loanTokens[0]);

        service = new CallOption(address(manager), address(ithil), 4e17, 86400 * 30, 86400 * 30, 0, loanTokens[0]);

        serviceAddress = address(service);
        ithil.approve(serviceAddress, 1e25);
        service.allocateIthil(1e25);

        vm.stopPrank();
    }

    function testSCOOpenPosition(uint256 daiAmount, uint256 daiLoan) public {
        collateralTokens[0] = manager.vaults(loanTokens[0]);
        collateralTokens[1] = address(ithil);
        IService.Order memory order = _openOrder1ForCredit(daiLoan, 0, block.timestamp, abi.encode(7));
        service.open(order);

        uint256 initialPrice = service.currentPrice();
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);

        // no fees, thus deposited amount and collaterals[0] are the same (vault 1:1 with underlying)
        assertEq(collaterals[0].amount, order.agreement.loans[0].amount);
        // due to the bump in the option price, we expect actual amount to be less than the virtual amount
        assertLe(collaterals[1].amount, (order.agreement.loans[0].amount * _rewards[7]) / initialPrice);
        // price was bumped by at least the allocation percentage (virtually) bougth
        assertGe(service.currentPrice(), initialPrice);
    }

    function testPriceDecay(uint256 daiAmount, uint256 daiLoan, uint64 warp) public {
        collateralTokens[0] = manager.vaults(loanTokens[0]);
        collateralTokens[1] = address(ithil);
        uint256 initialPrice = service.currentPrice();
        // This bumps the price
        IService.Order memory order = _openOrder1ForCredit(daiLoan, 0, block.timestamp, abi.encode(7));
        service.open(order);
        vm.warp(block.timestamp + warp);
        uint256 priceDecay = warp < 2 * service.halvingTime()
            ? (initialPrice * (2 * service.halvingTime() - warp)) / (2 * service.halvingTime())
            : 0;
        uint256 finalPrice = service.currentPrice();
        assertGe(finalPrice, priceDecay);
    }

    function testSCOClosePositionWithGain(uint256 daiAmount, uint256 daiLoan) public {
        testSCOOpenPosition(daiAmount, daiLoan);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        vm.startPrank(whales[loanTokens[0]]);
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(manager.vaults(loanTokens[0]), whaleBalance / 2);
        vm.stopPrank();
        uint256 assets = IVault(manager.vaults(loanTokens[0])).convertToAssets(collaterals[0].amount);
        vm.warp(block.timestamp + 8 * 30 * 86500);
        if (assets >= IVault(manager.vaults(loanTokens[0])).freeLiquidity()) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
            service.close(0, abi.encode(1e17));
        } else {
            service.close(0, abi.encode(1e17));
        }
    }

    function testSCOClosePositionWithLoss(uint256 daiAmount, uint256 daiLoan) public {
        testSCOOpenPosition(daiAmount, daiLoan);
        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        vm.startPrank(manager.vaults(loanTokens[0]));
        uint256 vaultBalance = IERC20(loanTokens[0]).balanceOf(manager.vaults(loanTokens[0]));
        IERC20(loanTokens[0]).transfer(whales[loanTokens[0]], vaultBalance / 2);
        vm.stopPrank();
        uint256 assets = IVault(manager.vaults(loanTokens[0])).convertToAssets(collaterals[0].amount);
        vm.warp(block.timestamp + 8 * 30 * 86500);
        if (assets >= IVault(manager.vaults(loanTokens[0])).freeLiquidity()) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
            service.close(0, abi.encode(1e17));
        } else {
            service.close(0, abi.encode(1e17));
        }
    }
}
