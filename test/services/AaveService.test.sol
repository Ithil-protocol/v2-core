// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { IAToken } from "../../src/interfaces/external/aave/IAToken.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";

contract AaveServiceTest is BaseIntegrationServiceTest {
    using GeneralMath for uint256;

    IManager internal immutable manager;
    AaveService internal immutable service;
    IERC20 internal constant dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    IAToken internal constant aDai = IAToken(0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE);

    address internal constant daiWhale = 0x252cd7185dB7C3689a571096D5B57D45681aA080;
    address internal constant aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), 58581858);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        service = new AaveService(address(manager), aavePool);
        vm.stopPrank();
    }

    function setUp() public {
        dai.approve(address(service), type(uint256).max);

        vm.deal(daiWhale, 1 ether);

        vm.startPrank(admin);
        // Create Vault: DAI
        manager.create(address(dai));
        // No caps for this service -> 100% of the liquidity can be used initially
        manager.setCap(address(service), address(dai), GeneralMath.RESOLUTION);

        vm.stopPrank();
    }

    function _prepareVaultsAndUser(uint256 daiAmount, uint256 daiMargin) internal returns (uint256, uint256) {
        // Modifications to be sure daiAmount + daiMargin <= dai.balanceOf(daiWhale) and same for weth
        daiAmount = daiAmount % dai.balanceOf(daiWhale);
        daiMargin = daiMargin % (dai.balanceOf(daiWhale) - daiAmount);
        daiAmount++;
        daiMargin++;

        // Fill DAI vault
        IVault daiVault = IVault(manager.vaults(address(dai)));
        vm.startPrank(daiWhale);
        dai.transfer(address(this), daiMargin);
        dai.approve(address(daiVault), daiAmount);
        daiVault.deposit(daiAmount, daiWhale);
        vm.stopPrank();

        return (daiAmount, daiMargin);
    }

    function _createOrder(uint256 daiLoan, uint256 daiMargin) internal returns (IService.Order memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(dai);

        uint256[] memory loans = new uint256[](1);
        loans[0] = daiLoan;

        uint256[] memory margins = new uint256[](1);
        margins[0] = daiMargin;

        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(aDai);

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = daiLoan + daiMargin;

        IService.Order memory order = Helper.createAdvancedOrder(
            tokens,
            loans,
            margins,
            itemTypes,
            collateralTokens,
            collateralAmounts,
            block.timestamp,
            ""
        );
        return order;
    }

    function _openOrder(
        uint256 daiAmount,
        uint256 daiLoan,
        uint256 daiMargin
    ) internal returns (uint256, uint256, uint256) {
        (daiAmount, daiMargin) = _prepareVaultsAndUser(daiAmount, daiMargin);
        // Loan must be less than amount otherwise Vault will revert
        // Since daiAmount > 0, the following does not revert for division by zero
        daiLoan = daiLoan % daiAmount;
        IService.Order memory order = _createOrder(daiLoan, daiMargin);

        service.open(order);
        return (daiAmount, daiLoan, daiMargin);
    }

    function testOpen(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin) public {
        (daiAmount, daiLoan, daiMargin) = _openOrder(daiAmount, daiLoan, daiMargin);
    }

    function testClose(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin, uint256 minAmountsOutDai) public {
        (daiAmount, daiLoan, daiMargin) = _openOrder(daiAmount, daiLoan, daiMargin);

        bytes memory data = abi.encode(minAmountsOutDai);

        (, IService.Collateral[] memory collaterals, , ) = service.getAgreement(1);
        if (collaterals[0].amount < minAmountsOutDai) {
            // Slippage check
            vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountOut()"))));
            service.close(0, data);
        } else {
            service.close(0, data);
        }
    }

    function testQuote(uint256 daiAmount, uint256 daiLoan, uint256 daiMargin) public {
        (daiAmount, daiLoan, daiMargin) = _openOrder(daiAmount, daiLoan, daiMargin);

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
