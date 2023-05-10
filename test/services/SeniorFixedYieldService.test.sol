// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { IAToken } from "../../src/interfaces/external/aave/IAToken.sol";
import { SeniorFixedYieldService } from "../../src/services/credit/SeniorFixedYieldService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract SeniorFixedYieldServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    SeniorFixedYieldService internal immutable service;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 76395332;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.prank(admin);
        service = new SeniorFixedYieldService(
            "Fixed yield 1m 1%",
            "FIXED-YIELD-1M1P",
            address(manager),
            1e16,
            86400 * 30
        );

        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        whales[loanTokens[0]] = 0x252cd7185dB7C3689a571096D5B57D45681aA080;
        serviceAddress = address(service);
    }

    function testFYSOpenPosition(uint256 daiAmount, uint256 daiLoan) public {
        collateralTokens[0] = manager.vaults(loanTokens[0]);
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 transformedAmount = daiAmount % whaleBalance;
        if (transformedAmount == 0) transformedAmount++;
        IService.Order memory order = _openOrder1ForCredit(daiLoan, daiLoan, block.timestamp, "");
        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);

        assertEq(collaterals[0].amount, daiLoan);
    }

    function testFYSClosePosition(uint256 daiAmount, uint256 daiLoan) public {
        testFYSOpenPosition(daiAmount, daiLoan);
        (IService.Loan[] memory loans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        service.close(0, abi.encode(0));
    }
}
