// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IService } from "../interfaces/IService.sol";

abstract contract Hooks is Ownable {
    function _open(IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _beforeOpening(IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _afterOpening(IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _close(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _beforeClosing(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _afterClosing(uint256 tokenID, IService.Agreement memory agreement, bytes memory data) internal virtual;

    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal virtual;
}
