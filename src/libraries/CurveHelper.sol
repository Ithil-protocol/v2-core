// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { ICurvePool } from "../interfaces/external/ICurvePool.sol";
import { IService } from "../interfaces/IService.sol";

/// @title    CurveHelper library
/// @author   Ithil
/// @notice   A library to interact with Curve pools
library CurveHelper {
    function quote(address pool, uint256 amount) internal view returns (uint256) {
        return (amount * 10**36) / ICurvePool(pool).get_virtual_price();
    }

    function deposit(address pool, IService.Agreement memory agreement) internal {
        if (agreement.loans.length == 2) {
            uint256[2] memory amounts;
            for (uint256 index = 0; index < 2; index++) {
                amounts[index] = agreement.loans[index].amount + agreement.loans[index].margin;
            }
            ICurvePool(pool).add_liquidity(amounts, agreement.collaterals[0].amount);
        } else if (agreement.loans.length == 3) {
            uint256[3] memory amounts;
            for (uint256 index = 0; index < 3; index++) {
                amounts[index] = agreement.loans[index].amount + agreement.loans[index].margin;
            }
            ICurvePool(pool).add_liquidity(amounts, agreement.collaterals[0].amount);
        } else if (agreement.loans.length == 4) {
            uint256[4] memory amounts;
            for (uint256 index = 0; index < 4; index++) {
                amounts[index] = agreement.loans[index].amount + agreement.loans[index].margin;
            }
            ICurvePool(pool).add_liquidity(amounts, agreement.collaterals[0].amount);
        }
    }

    function withdraw(address pool, IService.Agreement memory agreement, bytes calldata data) internal {
        if (agreement.loans.length == 2) {
            uint256[2] memory minAmountsOut = abi.decode(data, (uint256[2]));
            ICurvePool(pool).remove_liquidity(agreement.collaterals[0].amount, minAmountsOut);
        } else if (agreement.loans.length == 3) {
            uint256[3] memory minAmountsOut = abi.decode(data, (uint256[3]));
            ICurvePool(pool).remove_liquidity(agreement.collaterals[0].amount, minAmountsOut);
        } else if (agreement.loans.length == 4) {
            uint256[4] memory minAmountsOut = abi.decode(data, (uint256[4]));
            ICurvePool(pool).remove_liquidity(agreement.collaterals[0].amount, minAmountsOut);
        }
    }
}
