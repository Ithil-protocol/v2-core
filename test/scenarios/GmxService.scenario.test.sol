// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { GmxService } from "../../src/services/debit/GmxService.sol";

// import { console2 } from "forge-std/console2.sol";

interface IQuotable is IService {
    function quote(Agreement memory agreement) external view returns (uint256[] memory);
}

contract GmxScenarioTest is Test, IERC721Receiver {
    using GeneralMath for uint256;

    IQuotable internal constant gmxService = IQuotable(0x2B1050f9df5f210Ec121B92E23c96216DB966aa5);
    address internal constant admin = 0xabcdBC2EcB47642Ee8cf52fD7B88Fa42FBb69f98;
    IVault[] internal vaults;
    address[] internal loanTokens;
    mapping(address => address) internal whales;
    address[] internal collateralTokens;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 124506946;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vaults = new IVault[](1);
        loanTokens = new address[](1);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        whales[loanTokens[0]] = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
        collateralTokens[0] = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
        vaults[0] = IVault(0x8b002cf7380403329627149aA3D730E633BF1D33);
        vm.selectFork(forkId);
        vm.prank(admin);
        (bool success, ) = address(gmxService).call(abi.encodeWithSignature("toggleWhitelistFlag()"));
        require(success, "toggleWhitelistFlag failed");
    }

    function setUp() public virtual {
        vm.prank(whales[loanTokens[0]]);
        IERC20(loanTokens[0]).transfer(address(this), 1e10);
        IERC20(loanTokens[0]).approve(address(gmxService), type(uint256).max);
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
        uint256 margin = 1e8;
        uint256 loan = 1e8;
        IService.Loan[] memory loans = new IService.Loan[](1);
        IService.Collateral[] memory collaterals = new IService.Collateral[](1);
        loans[0] = IService.Loan(loanTokens[0], loan, margin, (5e16 * 2 ** 128) + 5e16);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, 0);
        IService.Agreement memory agreement = IService.Agreement(loans, collaterals, 0, IService.Status.OPEN);
        uint256[] memory quoted = gmxService.quote(agreement);
        collaterals[0] = IService.Collateral(IService.ItemType.ERC20, collateralTokens[0], 0, (quoted[0] * 99) / 100);
        // console2.log("collaterals[0].amount", collaterals[0].amount);
        agreement = IService.Agreement(loans, collaterals, 0, IService.Status.OPEN);
        IService.Order memory order = IService.Order(agreement, abi.encode(0));

        ///@dev Activate this to test!
        // gmxService.open(order);
    }
}
