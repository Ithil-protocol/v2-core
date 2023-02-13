// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IManager, Manager } from "../../src/Manager.sol";

contract BaseServiceTest is PRBTest, StdCheats, IERC721Receiver {
    address internal immutable admin = address(uint160(uint(keccak256(abi.encodePacked("admin")))));
    IManager internal immutable manager;

    constructor(string memory rpcUrl, uint256 blockNumber) {
        uint256 forkId = vm.createFork(vm.envString(rpcUrl), blockNumber);
        vm.selectFork(forkId);
        vm.deal(admin, 1 ether);

        vm.startPrank(admin);
        manager = IManager(new Manager());
        vm.stopPrank();
    }

    function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/)
        external
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
    
    /// Fills the vault and the user 
    /// @param amount the amount which will be deposited in the vault 
    /// @param margin the amount the user (address(this)) is refilled
    /// @param token the token 
    /// @param whale the address of the whale from whom tokens will be snatched
    function _prepareVaultsAndUser(uint256 amount, uint256 margin, IERC20 token, address whale) public returns (uint256, uint256) {
        amount = amount % token.balanceOf(whale); // 0 <= amount <= dai.balanceOf(whale) - 1
        margin = margin % (token.balanceOf(whale) - amount); // 0 <= margin + amount <= dai.balanceOf(whale) - 1

        IVault vault = IVault(manager.vaults(address(token)));
        vm.startPrank(whale);
        token.transfer(address(this), margin);
        token.approve(address(vault), amount);
        vault.deposit(amount, whale);
        vm.stopPrank();

        return (amount, margin);
    }
}
