// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { FeeCollectorService } from "../../src/services/neutral/FeeCollectorService.sol";
import { Service } from "../../src/services/Service.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { Ithil } from "../../src/Ithil.sol";
import { VeIthil } from "../../src/VeIthil.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { MockChainLinkOracle } from "../helpers/MockChainLinkOracle.sol";

contract Payer is Service {
    // Dummy service to produce fees
    constructor(address _manager) Service("Payer", "PAYER", _manager, 86400) {}

    function _close(
        uint256 tokenID,
        IService.Agreement memory agreement,
        bytes memory data
    ) internal virtual override {}

    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual override {}
}

contract FeeCollectorServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    MockChainLinkOracle internal immutable chainlinkOracleWeth;
    MockChainLinkOracle internal immutable chainlinkOracleUsdc;
    FeeCollectorService internal immutable service;
    Ithil internal immutable ithil;
    Service internal immutable payer;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 119065280;

    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant wethWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    IERC20 internal constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address internal constant usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    uint256[] internal rewards = new uint64[](12);

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        ithil = new Ithil(admin);
        // 1e17 means a fee percentage of 10%
        service = new FeeCollectorService(address(manager), address(weth), 1e17, address(oracle), address(dex));
        service.setTokenWeight(address(ithil), 1e18);
        payer = new Payer(address(manager));
        manager.setCap(address(payer), address(weth), GeneralMath.RESOLUTION, type(uint256).max);
        manager.setCap(address(payer), address(usdc), GeneralMath.RESOLUTION, type(uint256).max);
        chainlinkOracleWeth = new MockChainLinkOracle(8);
        chainlinkOracleUsdc = new MockChainLinkOracle(8);
        oracle.setPriceFeed(address(weth), address(chainlinkOracleWeth));
        oracle.setPriceFeed(address(usdc), address(chainlinkOracleUsdc));
        vm.stopPrank();

        loanLength = 3;
        loanTokens = new address[](3);
        loanTokens[0] = address(ithil);
        loanTokens[1] = address(weth);
        loanTokens[2] = address(usdc);
        whales[loanTokens[0]] = admin;
        whales[loanTokens[1]] = wethWhale;
        whales[loanTokens[2]] = usdcWhale;
        collateralTokens = new address[](1);
        collateralTokens[0] = address(ithil);
        serviceAddress = address(service);

        rewards[0] = 1059463094359295265;
        rewards[1] = 1122462048309372981;
        rewards[2] = 1189207115002721067;
        rewards[3] = 1259921049894873165;
        rewards[4] = 1334839854170034365;
        rewards[5] = 1414213562373095049;
        rewards[6] = 1498307076876681499;
        rewards[7] = 1587401051968199475;
        rewards[8] = 1681792830507429086;
        rewards[9] = 1781797436280678609;
        rewards[10] = 1887748625363386993;
        rewards[11] = 2000000000000000000;
    }

    function testFeeCollectorOpenPosition(uint256 amount, uint256 months) public returns (uint256) {
        bytes memory monthsLocked = abi.encode(uint256(months % 12));
        IService.Order memory order = _openOrder1(0, 0, amount, 0, block.timestamp, monthsLocked);
        uint256 initialBalance = ithil.balanceOf(address(this));
        service.open(order);
        assertEq(ithil.balanceOf(address(this)), initialBalance - order.agreement.loans[0].margin);

        return order.agreement.loans[0].margin;
    }

    function testFeeCollectorClosePosition(uint256 amount, uint256 feeTransfered, uint256 months) public {
        uint256 margin = testFeeCollectorOpenPosition(amount, months);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("BeforeExpiry()"))));
        service.close(0, "");

        vm.warp(block.timestamp + 86400 * 30 * (1 + (months % 12)));
        feeTransfered = feeTransfered % weth.balanceOf(wethWhale);
        vm.prank(wethWhale);
        weth.transfer(address(service), feeTransfered);

        uint256 initialWethBalance = weth.balanceOf(address(this));
        uint256 initialIthilBalance = ithil.balanceOf(address(this));
        service.close(0, "");
        assertEq(weth.balanceOf(address(this)), initialWethBalance + feeTransfered);
        assertEq(ithil.balanceOf(address(this)), initialIthilBalance + margin);
    }

    function testFeeCollectorHarvest() public {
        vm.startPrank(admin);
        chainlinkOracleWeth.setPrice(1800 * 1e8);
        chainlinkOracleUsdc.setPrice(1e8);
        vm.stopPrank();

        vm.prank(wethWhale);
        weth.transfer(address(payer), 1e18);

        vm.prank(usdcWhale);
        usdc.transfer(address(payer), 1e6);

        vm.startPrank(address(payer));
        weth.approve(manager.vaults(address(weth)), 1e18);
        usdc.approve(manager.vaults(address(usdc)), 1e6);
        manager.repay(address(weth), 1e18, 0, address(payer));
        manager.repay(address(usdc), 1e6, 0, address(payer));
        vm.stopPrank();

        // we should wait the fees to unlock, otherwise they cannot be harvested
        // (actually only feePercentage of the fees must be unlocked to be able to harvest)
        vm.warp(block.timestamp + 21600);

        // we want to test that WETH does not trigger a swap while USDC does
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        service.harvestAndSwap(tokens);

        address usdcVault = manager.vaults(address(usdc));

        // mock an order fill
        uint256 initialVaultBalance = usdc.balanceOf(usdcVault);

        uint256 amount = 1000 * 1e6;
        vm.prank(usdcWhale);
        usdc.transfer(address(dex), amount);
        dex.simuateOrderFulfillment(address(usdc), amount, usdcVault);

        assertTrue(usdc.balanceOf(usdcVault) == initialVaultBalance + amount);
    }
}
