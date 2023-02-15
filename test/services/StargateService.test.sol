// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { StargateService } from "../../src/services/debit/StargateService.sol";
import { IStargatePool } from "../../src/interfaces/external/stargate/IStargateLPStaking.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";

contract StargateServiceTest is BaseIntegrationServiceTest {
    StargateService internal immutable service;
    address internal constant stargateRouter = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address internal constant stargateLPStaking = 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b;
    uint16 internal constant usdcPoolID = 1;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
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

    function testOpen(uint256 amount0, uint256 loan0, uint256 margin0) public returns (bool) {
        IService.Order memory order = _openOrder1(amount0, loan0, margin0, 0, block.timestamp, "");
        bool success = true;
        if (_expectedMintedTokens(order.agreement.loans[0].amount + order.agreement.loans[0].margin) == 0) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("AmountTooLow()"))));
            service.open(order);
            success = false;
        } else service.open(order);
        return success;
    }

    function testClose(uint256 amount0, uint256 loan0, uint256 margin0, uint256 minAmountsOutusdc) public {
        bool success = testOpen(amount0, loan0, margin0);

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

    function testQuote(uint256 amount0, uint256 loan0, uint256 margin0) public {
        bool success = testOpen(amount0, loan0, margin0);
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
