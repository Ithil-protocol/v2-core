// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { StargateService } from "../../src/services/debit/StargateService.sol";
import { IStargatePool } from "../../src/interfaces/external/stargate/IStargateLPStaking.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseServiceTest } from "./BaseServiceTest.sol";
import { Helper } from "./Helper.sol";

contract StargateServiceTest is BaseServiceTest {
    StargateService internal immutable service;
    address internal constant stargateRouter = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address internal constant stargateLPStaking = 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b;
    uint16 internal constant usdcPoolID = 1;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new StargateService(address(manager), stargateRouter, stargateLPStaking);
        vm.stopPrank();
        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
        whales[loanTokens[0]] = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        collateralTokens[0] = 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56; //lpToken
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(loanTokens[0], 0);
    }

    function _expectedMintedTokens(uint256 amount) internal view returns (uint256 expected) {
        IStargatePool pool = IStargatePool(collateralTokens[0]);

        uint256 amountSD = amount / pool.convertRate();
        uint256 mintFeeSD = (amountSD * pool.mintFeeBP()) / 10000;
        amountSD = amountSD - mintFeeSD;
        expected = (amountSD * pool.totalSupply()) / pool.totalLiquidity();
    }

    function _openOrder(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin) internal returns (bool) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        amounts[0] = usdcAmount;
        loans[0] = usdcLoan;
        margins[0] = usdcMargin;
        IService.Order memory order = _prepareOpenOrder(amounts, loans, margins, 0, block.timestamp, "");

        bool success = true;
        if (_expectedMintedTokens(order.agreement.loans[0].amount + order.agreement.loans[0].margin) == 0) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("AmountTooLow()"))));
            service.open(order);
            success = false;
        } else service.open(order);

        return success;
    }

    function testOpen(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin) public returns (bool) {
        return _openOrder(usdcAmount, usdcLoan, usdcMargin);
    }

    function testClose(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin, uint256 minAmountsOutusdc) public {
        bool success = testOpen(usdcAmount, usdcLoan, usdcMargin);

        // TODO: add slippage check
        uint256 minAmountsOutusdc = 0;
        bytes memory data = abi.encode(minAmountsOutusdc);
        if (success) {
            (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
            if (collaterals[0].amount < minAmountsOutusdc) {
                // Slippage check
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
                service.close(0, data);
            } else {
                service.close(0, data);
            }
        }
    }

    function testQuote(uint256 usdcAmount, uint256 usdcLoan, uint256 usdcMargin) public {
        bool success = testOpen(usdcAmount, usdcLoan, usdcMargin);
        if (success) {
            (
                IService.Loan[] memory loan,
                IService.Collateral[] memory collaterals,
                uint256 createdAt,
                IService.Status status
            ) = service.getAgreement(1);

            IService.Agreement memory agreement = IService.Agreement(loan, collaterals, createdAt, status);
            (uint256[] memory profits, ) = service.quote(agreement);
        }
    }
}
