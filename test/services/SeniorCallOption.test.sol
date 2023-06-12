// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { Ithil } from "../../src/Ithil.sol";
import { SeniorCallOption } from "../../src/services/credit/SeniorCallOption.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";

contract SeniorCallOptionTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    SeniorCallOption internal immutable service;
    Ithil internal immutable ithil;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 76395332;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);

        ithil = new Ithil();
        loanLength = 1;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        whales[loanTokens[0]] = 0x252cd7185dB7C3689a571096D5B57D45681aA080;
        service = new SeniorCallOption(
            address(manager),
            address(this),
            address(ithil),
            86400 * 30 * 13,
            4e17,
            86400 * 30,
            loanTokens[0]
        );
        serviceAddress = address(service);
        ithil.approve(serviceAddress, 1e25);
        service.allocateIthil(1e25);

        vm.stopPrank();
    }

    function testSCOOpenPosition(uint256 daiAmount, uint256 daiLoan) public {
        collateralTokens[0] = manager.vaults(loanTokens[0]);
        uint256 whaleBalance = IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]);
        uint256 transformedAmount = daiAmount % whaleBalance;
        if (transformedAmount == 0) transformedAmount++;
        IService.Order memory order = _openOrder1ForCredit(daiLoan, daiLoan, block.timestamp, abi.encode(7));
        service.open(order);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);

        // TODO: check price change and allocations
    }

    function testSCOClosePosition(uint256 daiAmount, uint256 daiLoan) public {
        testSCOOpenPosition(daiAmount, daiLoan);
        (IService.Loan[] memory loans, IService.Collateral[] memory collaterals, , ) = service.getAgreement(0);
        uint256 assets = IVault(manager.vaults(loanTokens[0])).convertToAssets(collaterals[0].amount);
        if (assets >= IVault(manager.vaults(loanTokens[0])).freeLiquidity()) {
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientLiquidity()"))));
            service.close(0, abi.encode(1e17));
        } else service.close(0, abi.encode(1e17));
    }
}
