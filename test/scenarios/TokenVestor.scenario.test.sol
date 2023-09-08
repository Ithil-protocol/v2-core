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
import { TokenVestor } from "../../src/TokenVestor.sol";

contract TokenVestorScenarioTest is Test {
    using GeneralMath for uint256;

    address internal constant tokenVestor = 0x190B63111A0429B021DadDB750529f97df92198F;
    address internal constant admin = 0xabcdBC2EcB47642Ee8cf52fD7B88Fa42FBb69f98;
    address internal constant frax = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address internal constant fraxWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    string internal constant rpcUrl = "ARBITRUM_RPC_URL";
    uint256 internal constant blockNumber = 129235492;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        vm.prank(fraxWhale);
        IERC20(frax).approve(tokenVestor, type(uint256).max);
    }

    function _claimable(address user) internal returns (uint256) {
        (, bytes memory data) = tokenVestor.call(abi.encodeWithSignature("claimable(address)", user));
        return abi.decode(data, (uint256));
    }

    function _addAllocation(uint256 amount, uint256 start, uint256 duration, address to) internal {
        vm.prank(fraxWhale);
        (bool success, ) = tokenVestor.call(
            abi.encodeWithSignature("addAllocation(uint256,uint256,uint256,address)", amount, start, duration, to)
        );
        assert(success);
    }

    function _vestedAmount(
        address user
    ) internal returns (uint256 start, uint256 duration, uint256 amount, uint256 totalClaimed) {
        (, bytes memory data) = tokenVestor.call(abi.encodeWithSignature("vestedAmount(address)", user));
        (start, duration, amount, totalClaimed) = abi.decode(data, (uint256, uint256, uint256, uint256));
    }

    function testAllocate() public {
        _addAllocation(1e18, block.timestamp + 1 days, 2 days, address(this));

        (uint256 start, uint256 duration, uint256 amount, uint256 totalClaimed) = _vestedAmount(address(this));

        uint256 initialTimestamp = block.timestamp;

        assertEq(start, initialTimestamp + 1 days);
        assertEq(duration, 2 days);
        assertEq(amount, 1e18);
        assertEq(totalClaimed, 0);
        assertEq(_claimable(address(this)), 0);
        vm.warp(initialTimestamp + 2 days);
        assertEq(_claimable(address(this)), 5e17);
        vm.warp(initialTimestamp + 3 days);
        assertEq(_claimable(address(this)), 1e18);

        assertEq(_claimable(fraxWhale), 0);
        assertEq(_claimable(admin), 0);
    }
}
