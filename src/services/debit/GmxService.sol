// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewardRouterV2 } from "../../interfaces/external/gmx/IRewardRouterV2.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";
import { console2 } from "forge-std/console2.sol";

interface IRewardDistributor {
    function claimable(address _account) external view returns (uint256);
    function pendingRewards() external returns (uint256);
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

    constructor(address _manager, address _router) Service("GmxService", "GMX-SERVICE", _manager) {
        router = IRewardRouterV2(_router);
        glp = IERC20(router.glp());
        weth = IERC20(router.weth());
        glpManager = router.glpManager();
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        address token = agreement.loans[0].token;
        if (IERC20(token).allowance(address(this), glpManager) == 0)
            IERC20(token).safeApprove(glpManager, type(uint256).max);

        console2.log("Input", weth.balanceOf(address(this)));

        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = router.mintAndStakeGlp(
            token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            0,
            1 // minGlpOut
        );
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        /*router.handleRewards(
            true, // _shouldClaimGmx
            false, // _shouldStakeGmx
            true, // _shouldClaimEsGmx
            true, // _shouldStakeEsGmx
            true, // _shouldStakeMultiplierPoints
            true, // _shouldClaimWeth
            false // _shouldConvertWethToEth
        );*/

        IRewardDistributor r = IRewardDistributor(0x4e971a87900b931fF39d1Aad67697F49835400b6);

        router.unstakeAndRedeemGlp(
            agreement.loans[0].token,
            agreement.collaterals[0].amount,
            1, // minimum out
            address(this)
        );

        console2.log("Outpt", weth.balanceOf(address(this)));
        console2.log("Output GLP", IERC20(glp).balanceOf(address(this)));

        // if(agreement.loans[0].token != address(weth)) _swap();
    }

    function quote(Agreement memory agreement)
        public
        view
        override
        returns (uint256[] memory results, uint256[] memory)
    {}

    /*
    function _calculateRewards(bool isBaseReward, bool useGmx)
        internal
        view
        returns (uint256)
    {
        RewardTracker r;

        if (isBaseReward) {
            r = useGmx ? rewardTrackerGmx : rewardTrackerGlp;
        } else {
            r = useGmx ? stakedGmx : feeStakedGlp;
        }

        address distributor = r.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        uint256 distributorBalance = (isBaseReward ? gmxBaseReward : esGmx)
            .balanceOf(distributor);
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = r.PRECISION();
        uint256 cumulativeRewardPerToken = r.cumulativeRewardPerToken() +
            ((blockReward * precision) / r.totalSupply());

        if (cumulativeRewardPerToken == 0) return 0;

        return
            r.claimableReward(address(this)) +
            ((r.stakedAmounts(address(this)) *
                (cumulativeRewardPerToken -
                    r.previousCumulatedRewardPerToken(address(this)))) /
                precision);
    }
    */
}
