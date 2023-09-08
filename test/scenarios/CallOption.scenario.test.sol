// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager } from "../../src/interfaces/IManager.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { CallOption } from "../../src/services/credit/CallOption.sol";

contract CallOptionScenarioTest is Test, IERC721Receiver {
    using GeneralMath for uint256;

    IService internal callOptionService = IService(0x0822D0785E3f87fA245372e7f3aA4CEaF507a4c3);
    address internal constant admin = 0xabcdBC2EcB47642Ee8cf52fD7B88Fa42FBb69f98;
    address internal constant manager = 0x9136D8C2d303D47e927e269134eC3fB39576dB3E;
    IVault[] internal vaults;
    address[] internal loanTokens;
    mapping(address => address) internal whales;
    address[] internal collateralTokens;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 129229459;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vaults = new IVault[](1);
        loanTokens = new address[](1);
        collateralTokens = new address[](2);
        loanTokens[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        whales[loanTokens[0]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        collateralTokens[0] = 0x6b416C9727fb248C3097b5c1D10c39a7EBDFf239;
        collateralTokens[1] = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F; // FRAX
        vaults[0] = IVault(0x6b416C9727fb248C3097b5c1D10c39a7EBDFf239);
        vm.selectFork(forkId);
    }

    function setUp() public virtual {
        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(address(this), 1e10);
        IERC20(loanTokens[0]).approve(address(callOptionService), type(uint256).max);

        vm.prank(admin);
        IManager(manager).setCap(address(callOptionService), loanTokens[0], 1, 0);
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function testOpen() public {
        uint256 margin = 0;
        uint256 loan = 2.5e6;
        IService.Loan[] memory loans = new IService.Loan[](1);
        IService.Collateral[] memory collaterals = new IService.Collateral[](2);
        loans[0] = IService.Loan(loanTokens[0], loan, margin, 0);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, 0);
        IService.Agreement memory agreement = IService.Agreement(loans, collaterals, 0, IService.Status.OPEN);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, 0);
        collaterals[1] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[1], 0, 0);
        // console2.log("collaterals[0].amount", collaterals[0].amount);
        agreement = IService.Agreement(loans, collaterals, 0, IService.Status.OPEN);
        IService.Order memory order = IService.Order(agreement, abi.encode(11));

        ///@dev Activate this to test!
        callOptionService.open(order);
        vm.warp(block.timestamp + 1 * 100);
        // let's open another one!
        order = IService.Order(agreement, abi.encode(11));
        callOptionService.open(order);
    }

    function testClose() public {
        testOpen();
        vm.warp(block.timestamp + 13 * 21600);
        (
            IService.Loan[] memory actualLoans,
            IService.Collateral[] memory actualCollaterals,
            uint256 createdAt,
            IService.Status status
        ) = callOptionService.getAgreement(0);

        uint256 fraxBalance = IERC20(collateralTokens[1]).balanceOf(address(this));
        uint256 calledPortion = 7.5e17;
        callOptionService.close(0, abi.encode(calledPortion));
        fraxBalance = IERC20(collateralTokens[1]).balanceOf(address(this));
        (actualLoans, actualCollaterals, createdAt, status) = callOptionService.getAgreement(1);
        calledPortion = 6e17;
        uint256 initialAdminUsdcBalance = IERC20(collateralTokens[0]).balanceOf(admin);
        uint256 initialThisUsdcBalance = IERC20(loanTokens[0]).balanceOf(address(this));
        callOptionService.close(1, abi.encode(calledPortion));
    }
}
