// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { FeeCollector } from "../../src/services/credit/FeeCollector.sol";
import { Service } from "../../src/services/Service.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { Ithil } from "../../src/Ithil.sol";

import { console2 } from "forge-std/console2.sol";

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

contract FeeCollectorTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    FeeCollector internal immutable service;
    Ithil internal immutable ithil;
    Service internal immutable payer;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 55895589;
    IERC20 internal immutable weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal immutable wethWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        ithil = new Ithil();
        service = new FeeCollector(address(manager), address(weth), address(ithil), 2592000, 1e17);
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
    }

    function testFeeCollectorOpenPosition(uint256 amount) public returns (uint256) {
        IService.Order memory order = _openOrder1(0, 0, amount, 0, block.timestamp, "");
        uint256 initialBalance = ithil.balanceOf(address(this));
        service.open(order);
        assertEq(ithil.balanceOf(address(this)), initialBalance - order.agreement.loans[0].margin);
        assertEq(service.totalCollateral(), order.agreement.loans[0].margin);
        return order.agreement.loans[0].margin;
    }

    function testFeeCollectorClosePosition(uint256 amount, uint256 feeTransfered) public {
        uint256 margin = testFeeCollectorOpenPosition(amount);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("BeforeExpiry()"))));
        service.close(0, "");

        vm.warp(block.timestamp + service.duration());
        feeTransfered = feeTransfered % weth.balanceOf(wethWhale);
        vm.prank(wethWhale);
        weth.transfer(address(service), feeTransfered);

        uint256 initialWethBalance = weth.balanceOf(address(this));
        uint256 initialIthilBalance = ithil.balanceOf(address(this));
        service.close(0, "");
        console2.log("5");
        assertEq(weth.balanceOf(address(this)), initialWethBalance + feeTransfered);
        console2.log("6");
        assertEq(ithil.balanceOf(address(this)), initialIthilBalance + margin);
        console2.log("7");
    }
}
