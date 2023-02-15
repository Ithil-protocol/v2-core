// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewardRouterV2 } from "../../interfaces/external/gmx/IRewardRouterV2.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

interface IRewardTracker {
    function distributor() external view returns (address);
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
    function stakedAmounts(address _account) external view returns (uint256);
    function updateRewards() external;
    function stake(address _depositToken, uint256 _amount) external;
    function unstake(address _depositToken, uint256 _amount) external;
    function tokensPerInterval() external view returns (uint256);
    function claim(address _receiver) external returns (uint256);
    function claimForAccount(address _account, address _receiver) external returns (uint256);
    function claimable(address _account) external view returns (uint256);
    function averageStakedAmounts(address _account) external view returns (uint256);
    function cumulativeRewards(address _account) external view returns (uint256);
}

interface IRewardDistributor {
    function rewardToken() external view returns (address);
    function tokensPerInterval() external view returns (uint256);
    function pendingRewards() external view returns (uint256);
    function distribute() external returns (uint256);
}

/// @title    GmxService contract
/// @author   Ithil
/// @notice   A service to perform margin trading on the GLP token
contract GmxService is SecuritisableService {
    using SafeERC20 for IERC20;

    IRewardRouterV2 public immutable router;
    IERC20 public immutable glp;
    IERC20 public immutable weth;
    address public immutable glpManager;

    constructor(address _manager, address _router)
        Service("GmxService", "GMX-SERVICE", _manager)
    {
        router = IRewardRouterV2(_router);
        glp = IERC20(router.glp());
        weth = IERC20(router.weth());
        glpManager = router.glpManager();
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        address token = agreement.loans[0].token;
        if (IERC20(token).allowance(address(this), glpManager) == 0)
            IERC20(token).safeApprove(glpManager, type(uint256).max);

        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = router.mintAndStakeGlp(
            token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            0,
            1 // minGlpOut
        );
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        router.unstakeAndRedeemGlp(
            agreement.loans[0].token,
            agreement.collaterals[0].amount,
            1, // minimum out
            address(this)
        );

        // TODO if(agreement.loans[0].token != address(weth)) _swap();
    }

    function quote(Agreement memory agreement)
        public
        view
        override
        returns (uint256[] memory results, uint256[] memory)
    {
        // TODO
    }
}
