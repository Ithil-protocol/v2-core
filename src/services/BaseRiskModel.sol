// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IService } from "../interfaces/IService.sol";

abstract contract BaseRiskModel {
    function _checkRiskiness(IService.Loan memory loan, uint256 freeLiquidity) internal virtual;
}
