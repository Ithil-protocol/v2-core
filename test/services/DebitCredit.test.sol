// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { Ithil } from "../../src/Ithil.sol";
import { SeniorCallOption } from "../../src/services/credit/SeniorCallOption.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";

import { console2 } from "forge-std/console2.sol";

contract DebitCreditTest is Test, IERC721Receiver {
    // test in which we add Aave, Gmx, feeCollector and call option
    // due to the complexity of the setup, fuzzy testing is limited
    // Due to the simmetry between Aave and Gmx services, the states to be considered are three:
    // 1. Aave position open or not
    // 2. Call option open or not
    // 3. Fee collector deposit done or not

    using GeneralMath for uint256;
    // The owner of the manager and all services
    address internal immutable admin = address(uint160(uint(keccak256(abi.encodePacked("admin")))));
    // who liquidates debit positions and also harvest fees (no need of two addresses)
    address internal immutable automator = address(uint160(uint(keccak256(abi.encodePacked("automator")))));
    // vanilla depositor to the Vault
    address internal immutable liquidityProvider =
        address(uint160(uint(keccak256(abi.encodePacked("liquidityProvider")))));
    // depositor of the call option: locks some capital and may exercise at maturity
    address internal immutable callOptionSigner =
        address(uint160(uint(keccak256(abi.encodePacked("callOptionSigner")))));
    // user of Aave service: posts margin and takes loan
    address internal immutable aaveUser = address(uint160(uint(keccak256(abi.encodePacked("aaveUser")))));
    // user of Gmx service: posts margin and takes loan
    address internal immutable gmxUser = address(uint160(uint(keccak256(abi.encodePacked("gmxUser")))));
    // depositor of the fee collector service: wants to obtain fees from Ithil
    address internal immutable feeCollectorDepositor =
        address(uint160(uint(keccak256(abi.encodePacked("feeCollectorDepositor")))));
    // treasury
    address internal immutable treasury = address(uint160(uint(keccak256(abi.encodePacked("treasury")))));

    IManager internal immutable manager;

    AaveService internal immutable aaveService;
    SeniorCallOption internal immutable callOptionService;
    Ithil internal immutable ithil;

    address internal constant aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    address internal constant usdcWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address internal constant gmxRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address internal constant gmxRouterV2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 76396000;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);
        vm.prank(usdcWhale);
        IERC20(usdc).transfer(address(admin), 1);
        vm.startPrank(admin);
        manager = IManager(new Manager());
        ithil = new Ithil();
        aaveService = new AaveService(address(manager), aavePool, 30 * 86400);

        // Create a vault for USDC
        // recall that the admin needs 1e-6 USDC to create the vault
        IERC20(usdc).approve(address(manager), 1);
        manager.create(usdc);

        // first price is 0.2 USDC
        callOptionService = new SeniorCallOption(
            address(manager),
            treasury,
            address(ithil),
            86400 * 30 * 13,
            2e5,
            86400 * 30,
            usdc
        );
        vm.stopPrank();
    }

    function setUp() public {
        // ithil must be allocated to start
        vm.startPrank(admin);
        ithil.approve(address(callOptionService), 1e7 * 1e18);
        callOptionService.allocateIthil(1e7 * 1e18);

        // give 1m Ithil to fee depositor
        ithil.transfer(feeCollectorDepositor, 1e6 * 1e18);
        vm.stopPrank();
        // give 100k to everybody needing them
        vm.startPrank(usdcWhale);
        IERC20(usdc).transfer(liquidityProvider, 1e8);
        IERC20(usdc).transfer(callOptionSigner, 1e8);
        IERC20(usdc).transfer(aaveUser, 1e8);
        IERC20(usdc).transfer(gmxUser, 1e8);
        vm.stopPrank();
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _openAavePosition(uint256 margin, uint256 loan) internal {
        // Opens an Aave position in all cases (no check on interest)
        IService.Loan[] memory loans = new IService.Loan[](1);
        loans[0] = IService.Loan(address(usdc), loan, margin, 1e18);
        IService.Collateral[] memory collaterals = new IService.Collateral[](1);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, aavePool, 0, 0);
        IService.Agreement memory agreement = IService.Agreement(
            loans,
            collaterals,
            block.timestamp,
            IService.Status.OPEN
        );
        IService.Order memory order = IService.Order(agreement, abi.encode(""));
        aaveService.open(order);
    }

    function _openCallOption(uint256 loan, uint256 monthsLocked) internal {
        IService.Loan[] memory loans = new IService.Loan[](1);
        loans[0] = IService.Loan(address(usdc), loan, 0, 1e18);
        IService.Collateral[] memory collaterals = new IService.Collateral[](2);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, manager.vaults(usdc), 0, 0);
        collaterals[1] = IService.Collateral(IService.ItemType.ERC20, address(ithil), 0, 0);
        IService.Agreement memory agreement = IService.Agreement(
            loans,
            collaterals,
            block.timestamp,
            IService.Status.OPEN
        );
        IService.Order memory order = IService.Order(agreement, abi.encode(monthsLocked));
        callOptionService.open(order);
    }

    function testCallOption() public {
        // In this test, the user puts a call option in various states
        // notice that the call option does not need any former liquidity in the vault
        vm.startPrank(callOptionSigner);
        IERC20(usdc).approve(address(callOptionService), 1e6);
        _openCallOption(1e6, 1);
        vm.stopPrank();

        (, IService.Collateral[] memory collaterals, , ) = callOptionService.getAgreement(0);
        console2.log("collaterals[0]", collaterals[0].amount);
        console2.log("collaterals[1]", collaterals[1].amount);
    }
}
