// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract BaseServiceTest is IERC721Receiver {
    address internal immutable admin = address(uint160(uint(keccak256(abi.encodePacked("admin")))));

    function onERC721Received(address /*operator*/, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/)
        external
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
