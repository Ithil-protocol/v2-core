// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IService } from "../interfaces/IService.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BaseRiskModel is Ownable {
    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal virtual;
}
