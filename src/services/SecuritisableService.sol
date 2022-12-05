// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Service } from "./Service.sol";

abstract contract SecuritisableService is Service {
    using SafeERC20 for IERC20;

    event LenderWasChanged(uint256 indexed id, address indexed newLender);

    function purchaseCredit(uint256 id, address purchaser) external {
        assert(_exists(id));

        // repay debt and assign
        uint256 toPay = price(id);
        IERC20(agreements[id].held.token).safeTransferFrom(msg.sender, address(this), toPay);
        agreements[id].lender = purchaser;

        // TODO repay the vault
        /// manager.repay(toPay)

        emit LenderWasChanged(id, purchaser);
    }

    function price(uint256 id) public view returns (uint256) {
        uint256 fees = 1;
        BaseAgreement memory agreement = agreements[id];

        return agreement.held.amount + fees * (1 - riskFactors[agreement.held.token]);
    }
}
