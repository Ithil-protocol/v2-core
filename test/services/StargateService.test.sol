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
    address internal constant stargateRouter = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    address internal constant stargateLPStaking = 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176;
    uint16 internal constant usdcPoolID = 1;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 55895589;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new StargateService(address(manager), stargateRouter, stargateLPStaking);
        vm.stopPrank();
        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // usdc
        whales[loanTokens[0]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        collateralTokens[0] = 0x892785f33CdeE22A30AEF750F285E18c18040c3e; //lpToken
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

    function testStargateIntegrationOpenPosition(uint256 amount0, uint256 loan0, uint256 margin0)
        public
        returns (bool)
    {
        IService.Order memory order = _openOrder1(amount0, loan0, margin0, 0, block.timestamp, "");
        bool success = true;
        if (_expectedMintedTokens(order.agreement.loans[0].amount + order.agreement.loans[0].margin) == 0) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("AmountTooLow()"))));
            service.open(order);
            success = false;
        } else service.open(order);
        return success;
    }

    function testStargateIntegrationClosePosition(uint256 amount0, uint256 loan0, uint256 margin0) public {
        bool success = testStargateIntegrationOpenPosition(amount0, loan0, margin0);

        uint256 minAmountsOut = 0; // TODO make it fuzzy
        bytes memory data = abi.encode(minAmountsOut);
        if (success) {
            (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
            if (collaterals[0].amount < minAmountsOut) {
                // Slippage check
                vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
                service.close(0, data);
            } else {
                service.close(0, data);
            }
        }
    }

    function testStargateIntegrationQuoter(uint256 amount0, uint256 loan0, uint256 margin0) public {
        bool success = testStargateIntegrationOpenPosition(amount0, loan0, margin0);
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

    // TODO test quoter
}
