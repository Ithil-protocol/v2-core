// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewardRouter, IRewardRouterV2, IGlpManager, IUsdgVault } from "../../interfaces/external/gmx/IGmx.sol";
import { ConstantRateModel } from "../../irmodels/ConstantRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    GmxService contract
/// @author   Ithil
/// @notice   A service to perform margin trading on the GLP token
contract GmxService is Whitelisted, ConstantRateModel, DebitService {
    using SafeERC20 for IERC20;

    IRewardRouter public immutable router;
    IRewardRouterV2 public immutable routerV2;
    IERC20 public immutable glp;
    IERC20 public immutable weth;
    IGlpManager public immutable glpManager;
    IUsdgVault public immutable usdgVault;

    constructor(address _manager, address _router, address _routerV2, uint256 _deadline)
        Service("GmxService", "GMX-SERVICE", _manager, _deadline)
    {
        router = IRewardRouter(_router);
        routerV2 = IRewardRouterV2(_routerV2);
        glp = IERC20(routerV2.glp());
        weth = IERC20(routerV2.weth());
        glpManager = IGlpManager(routerV2.glpManager());
        usdgVault = IUsdgVault(glpManager.vault());
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        uint256 minGlpOut = abi.decode(data, (uint256));

        address token = agreement.loans[0].token;
        if (IERC20(token).allowance(address(this), address(glpManager)) == 0)
            IERC20(token).safeApprove(address(glpManager), type(uint256).max);

        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = routerV2.mintAndStakeGlp(
            token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            0,
            minGlpOut
        );
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        uint256 minAmountOut = abi.decode(data, (uint256));

        routerV2.unstakeAndRedeemGlp(
            agreement.loans[0].token,
            agreement.collaterals[0].amount,
            minAmountOut,
            address(this)
        );

        // TODO if(agreement.loans[0].token != address(weth)) _swapWethToToken();
    }

    function quote(Agreement memory agreement)
        public
        view
        override
        returns (uint256[] memory results, uint256[] memory)
    {
        uint256 aumInUsdg = glpManager.getAumInUsdg(false);
        uint256 glpSupply = glp.totalSupply();

        // agreement.collaterals[0].amount == GLP amount
        uint256 usdgAmount = (agreement.collaterals[0].amount * aumInUsdg) / glpSupply;
        results[0] = usdgVault.getRedemptionAmount(agreement.loans[0].token, usdgAmount);
    }

    function harvest() public {
        router.handleRewards(false, false, false, false, false, true, false);
    }
}
