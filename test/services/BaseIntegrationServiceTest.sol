// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { OrderHelper } from "../helpers/OrderHelper.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { Oracle } from "../../src/Oracle.sol";
import { MockDex } from "../helpers/MockDex.sol";

contract BaseIntegrationServiceTest is Test, IERC721Receiver {
    address internal constant admin = address(uint160(uint256(keccak256(abi.encodePacked("admin")))));
    IManager internal immutable manager;
    Oracle internal immutable oracle;
    MockDex internal immutable dex;

    address[] internal loanTokens;
    mapping(address => address) internal whales;
    address[] internal collateralTokens;
    uint256 internal loanLength;

    address internal serviceAddress;

    constructor(string memory rpcUrl, uint256 blockNumber) {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        oracle = new Oracle();
        dex = new MockDex();
        vm.stopPrank();
    }

    function setUp() public virtual {
        for (uint256 i = 0; i < loanLength; i++) {
            IERC20(loanTokens[i]).approve(serviceAddress, type(uint256).max);

            vm.deal(whales[loanTokens[i]], 1 ether);
        }
        for (uint256 i = 0; i < loanLength; i++) {
            if (manager.vaults(loanTokens[i]) == address(0)) {
                vm.prank(whales[loanTokens[i]]);
                IERC20(loanTokens[i]).transfer(admin, 1);
                vm.startPrank(admin);
                IERC20(loanTokens[i]).approve(address(manager), 1);
                manager.create(loanTokens[i]);
                vm.stopPrank();
            }
            // No caps for this service -> 100% of the liquidity can be used initially
            vm.startPrank(admin);
            manager.setCap(serviceAddress, loanTokens[i], GeneralMath.RESOLUTION, type(uint256).max);
            vm.stopPrank();
        }
        vm.prank(admin);
        (bool success, ) = serviceAddress.call(abi.encodeWithSignature("toggleWhitelistFlag()"));
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// Fills the vault
    /// @param amount the amount which will be deposited in the vault
    /// @param token the token
    /// @param needsBumping whether we need to have amount > 0 (some services could fail)
    function _depositAmountInVault(address token, uint256 amount, bool needsBumping) internal returns (uint256) {
        if (IERC20(token).balanceOf(whales[address(token)]) > 0) {
            // 0 <= amount <= dai.balanceOf(whale) - 1
            amount = amount % IERC20(token).balanceOf(whales[address(token)]);
            if (needsBumping && amount == 0) amount++;

            IVault vault = IVault(manager.vaults(token));
            vm.startPrank(whales[token]);
            IERC20(token).approve(address(vault), amount);
            vault.deposit(amount, whales[token]);
            vm.stopPrank();
            // amount is modified, so we return new value
            return amount;
        } else {
            return 0;
        }
    }

    /// Fills the user
    /// @param margin the amount which will be deposited in the vault
    /// @param token the token
    /// @param needsBumping whether we need to have amount > 0 (some services could fail if not)
    function _giveMarginToUser(address token, uint256 margin, bool needsBumping) internal returns (uint256) {
        margin = margin % (IERC20(token).balanceOf(whales[token])); // 0 <= margin <= dai.balanceOf(whale) - 1
        if (needsBumping && margin == 0) margin++;

        vm.prank(whales[token]);
        IERC20(token).transfer(address(this), margin);

        // margin is modified, so we return new value
        return margin;
    }

    function _vectorizedOpenOrder(
        uint256[] memory amounts,
        uint256[] memory loans,
        uint256[] memory margins,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory) {
        for (uint256 i = 0; i < loanLength; i++) {
            amounts[i] = _depositAmountInVault(loanTokens[i], amounts[i], true);
            margins[i] = _giveMarginToUser(loanTokens[i], margins[i], true);
            // amounts are bumped so the following never reverts
            loans[i] = loans[i] % amounts[i];
        }
        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = collateralAmount;
        return
            OrderHelper.createAdvancedOrder(
                loanTokens,
                loans,
                margins,
                itemTypes,
                collateralTokens,
                collateralAmounts,
                time,
                data
            );
    }

    function _vectorizedOpenOrderForCredit(
        uint256[] memory loans,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory) {
        for (uint256 i = 0; i < loanLength; i++) {
            loans[i] = _giveMarginToUser(loanTokens[i], loans[i], true);
        }

        // allow for 2 slots to cover the case of the call option
        IService.ItemType[] memory itemTypes = new IService.ItemType[](2);
        itemTypes[0] = IService.ItemType.ERC20;
        itemTypes[1] = IService.ItemType.ERC20;

        uint256[] memory collateralAmounts = new uint256[](2);
        collateralAmounts[0] = collateralAmount;
        return
            OrderHelper.createAdvancedOrder(
                loanTokens,
                loans,
                new uint256[](1),
                itemTypes,
                collateralTokens,
                collateralAmounts,
                time,
                data
            );
    }

    function _openOrder0(
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory order) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        return _vectorizedOpenOrder(amounts, loans, margins, collateralAmount, time, data);
    }

    function _openOrder1(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory order) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        amounts[0] = amount0;
        loans[0] = loan0;
        margins[0] = margin0;
        return _vectorizedOpenOrder(amounts, loans, margins, collateralAmount, time, data);
    }

    function _openOrder1ForCredit(
        uint256 loan0,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory order) {
        uint256[] memory loans = new uint256[](loanLength);
        loans[0] = loan0;
        return _vectorizedOpenOrderForCredit(loans, collateralAmount, time, data);
    }

    function _openOrder2(
        uint256 amount0,
        uint256 loan0,
        uint256 margin0,
        uint256 amount1,
        uint256 loan1,
        uint256 margin1,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory order) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        amounts[0] = amount0;
        loans[0] = loan0;
        margins[0] = margin0;
        amounts[1] = amount1;
        loans[1] = loan1;
        margins[1] = margin1;
        return _vectorizedOpenOrder(amounts, loans, margins, collateralAmount, time, data);
    }

    function _openOrder3(
        uint256 loan0,
        uint256 margin0,
        uint256 loan1,
        uint256 margin1,
        uint256 loan2,
        uint256 margin2,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) internal returns (IService.Order memory order) {
        uint256[] memory amounts = new uint256[](loanLength);
        uint256[] memory loans = new uint256[](loanLength);
        uint256[] memory margins = new uint256[](loanLength);
        // amount calculation is necessary to avoid a stack too deep
        amounts[0] =
            IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]) -
            (margin0 % IERC20(loanTokens[0]).balanceOf(whales[loanTokens[0]]));
        loans[0] = loan0;
        margins[0] = margin0;
        amounts[1] =
            IERC20(loanTokens[1]).balanceOf(whales[loanTokens[1]]) -
            (margin1 % (IERC20(loanTokens[1]).balanceOf(whales[loanTokens[1]])));
        loans[1] = loan1;
        margins[1] = margin1;
        amounts[2] =
            IERC20(loanTokens[2]).balanceOf(whales[loanTokens[2]]) -
            (margin2 % (IERC20(loanTokens[2]).balanceOf(whales[loanTokens[2]])));
        loans[2] = loan2;
        margins[2] = margin2;
        return _vectorizedOpenOrder(amounts, loans, margins, collateralAmount, time, data);
    }
}
