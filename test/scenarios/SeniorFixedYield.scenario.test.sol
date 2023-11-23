// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { GeneralMath } from "../helpers/GeneralMath.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { FixedYieldService } from "../../src/services/credit/FixedYieldService.sol";

contract SFYScenarioTest is Test, IERC721Receiver {
    using GeneralMath for uint256;

    IService internal constant FixedYieldService = IService(0x40A87286EF87e17a48a5b266F94c918A53289956);
    address internal constant admin = 0xabcdBC2EcB47642Ee8cf52fD7B88Fa42FBb69f98;
    IVault[] internal vaults;
    address[] internal loanTokens;
    address[] internal collateralTokens;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 128267144;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vaults = new IVault[](1);
        loanTokens = new address[](1);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDC
        collateralTokens[0] = 0x8b002cf7380403329627149aA3D730E633BF1D33;
        vaults[0] = IVault(0x8b002cf7380403329627149aA3D730E633BF1D33);
        vm.selectFork(forkId);
    }

    function onERC721Received(
        address,
        /*operator*/ address,
        /*from*/ uint256,
        /*tokenId*/ bytes calldata /*data*/
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function testClose() public {
        vm.startPrank(admin);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        FixedYieldService.close(0, abi.encode(0));
        vm.stopPrank();
    }
}
