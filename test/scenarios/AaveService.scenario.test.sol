// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { AaveService } from "../../src/services/debit/AaveService.sol";

contract AaveScenarioTest is Test, IERC721Receiver {
    using GeneralMath for uint256;

    IService internal constant aaveService = IService(0xb18865C919ADd78862D412AD253536d4C1C178Db);
    address internal constant admin = 0xabcdBC2EcB47642Ee8cf52fD7B88Fa42FBb69f98;
    IVault[] internal vaults;
    address[] internal loanTokens;
    mapping(address => address) internal whales;
    address[] internal collateralTokens;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 123788806;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vaults = new IVault[](1);
        loanTokens = new address[](1);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        whales[loanTokens[0]] = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        collateralTokens[0] = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
        vaults[0] = IVault(0x6b416C9727fb248C3097b5c1D10c39a7EBDFf239);
        vm.selectFork(forkId);
        vm.prank(admin);
        (bool success, ) = address(aaveService).call(abi.encodeWithSignature("toggleWhitelistFlag()"));
        require(success, "toggleWhitelistFlag failed");
    }

    function setUp() public virtual {
        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(address(this), 1e10);
        IERC20(loanTokens[0]).approve(address(aaveService), type(uint256).max);
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function testOpen() public {
        uint256 margin = 1e9;
        uint256 loan = 1e9;
        uint256 collateral = ((margin + loan) * 99) / 100;
        IService.Loan[] memory loans = new IService.Loan[](1);
        IService.Collateral[] memory collaterals = new IService.Collateral[](1);
        loans[0] = IService.Loan(loanTokens[0], loan, margin, (5e16 * 2 ** 128) + 5e16);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, collateral);
        IService.Agreement memory agreement = IService.Agreement(loans, collaterals, 0, IService.Status.OPEN);
        IService.Order memory order = IService.Order(agreement, abi.encode(0));

        // uint256 freeLiquidity = vaults[0].freeLiquidity();
        // console2.log("freeLiquidity", freeLiquidity);
        // (, bytes memory data) = address(aaveService).staticcall(
        //     abi.encodeWithSignature(
        //         "computeBaseRateAndSpread(address,uint256,uint256,uint256)",
        //         loanTokens[0],
        //         loan,
        //         margin,
        //         freeLiquidity
        //     )
        // );
        // (uint256 base, uint256 spread) = abi.decode(data, (uint256, uint256));
        // console2.log("base", base);
        // console2.log("spread", spread);
        aaveService.open(order);
    }
}
