// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { FeeCollectorService } from "../../src/services/neutral/FeeCollectorService.sol";
import { Service } from "../../src/services/Service.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { Ithil } from "../../src/Ithil.sol";
import { VeIthil } from "../../src/VeIthil.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";

contract Payer is Service {
    // Dummy service to produce fees
    // TODO: test fee generation
    constructor(address _manager) Service("Payer", "PAYER", _manager) {}

    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data)
        internal
        virtual
        override
    {}

    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual override {}
}

contract FeeCollectorServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    FeeCollectorService internal immutable service;
    Ithil internal immutable ithil;
    Service internal immutable payer;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 55895589;
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant wethWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    uint256[] internal rewards = new uint64[](12);

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        ithil = new Ithil();
        service = new FeeCollectorService(address(manager), address(weth), 1e17);
        service.setTokenWeight(address(ithil), 1e18);
        payer = new Payer(address(manager));
        manager.setCap(address(payer), address(weth), GeneralMath.RESOLUTION);
        vm.stopPrank();

        loanLength = 1;
        loanTokens = new address[](1);
        loanTokens[0] = address(ithil);
        whales[loanTokens[0]] = admin;
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
        assertEq(service.totalLoans(), order.agreement.loans[0].margin.safeMulDiv(rewards[months % 12], 1e18));
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
}
