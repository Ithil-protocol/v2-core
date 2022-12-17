// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IService is IERC721Enumerable {
    event BaseRiskSpreadWasUpdated(address indexed asset, uint256 indexed id, uint256 newValue);
    event LockWasToggled(bool status);
    event GuardianWasUpdated(address indexed newGuardian);
    error Locked();
}
