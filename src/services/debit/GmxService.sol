// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IRewardRouter,
    IRewardRouterV2,
    IGlpManager,
    IUsdgVault,
    IRewardTracker
} from "../../interfaces/external/gmx/IGmx.sol";
import { AuctionRateModel } from "../../irmodels/AuctionRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    GmxService contract
/// @author   Ithil
/// @notice   A service to perform margin trading on the GLP token
contract GmxService is Whitelisted, AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    IRewardRouter public immutable router;
    IRewardRouterV2 public immutable routerV2;
    IERC20 public immutable glp;
    IERC20 public immutable weth;
    IRewardTracker public immutable rewardTracker;
    IGlpManager public immutable glpManager;
    IUsdgVault public immutable usdgVault;

    // We apply operator theory to distribute rewards evenly, similar to fee collector
    // although now we should be careful not to include weth balance due to usage
    // moreover, there is no minting in place and GLP are staked, so we need an extra
    // "totalCollateral" variable to register the sum of all collaterals for all open positions
    uint256 public totalRewards;
    uint256 public totalCollateral;
    uint256 public totalVirtualDeposits;
    mapping(uint256 => uint256) public virtualDeposit;

    error InvalidToken();
    error ZeroGlpSupply();

    constructor(
        address _manager,
        address _router,
        address _routerV2,
        uint256 _deadline
    ) Service("GmxService", "GMX-SERVICE", _manager, _deadline) {
        router = IRewardRouter(_router);
        routerV2 = IRewardRouterV2(_routerV2);
        glp = IERC20(routerV2.glp());
        weth = IERC20(routerV2.weth());

        rewardTracker = IRewardTracker(routerV2.feeGlpTracker());
        glpManager = IGlpManager(routerV2.glpManager());
        usdgVault = IUsdgVault(glpManager.vault());
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        if (IERC20(agreement.loans[0].token).allowance(address(this), address(glpManager)) == 0) {
            IERC20(agreement.loans[0].token).approve(address(glpManager), type(uint256).max);
        }
        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = routerV2.mintAndStakeGlp(
            agreement.loans[0].token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            0,
            agreement.collaterals[0].amount
        );

        totalCollateral += agreement.collaterals[0].amount;
        // This check is here to protect the msg.sender from slippage, therefore reentrancy is not an issue
        if (totalCollateral == 0) revert ZeroGlpSupply();
        // we assign a virtual deposit of v * A / S, __afterwards__ we update the total deposits
        virtualDeposit[id] =
            (agreement.collaterals[0].amount * (totalRewards + totalVirtualDeposits)) /
            totalCollateral;
        totalVirtualDeposits += virtualDeposit[id];
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes memory data) internal override {
        uint256 minAmountOut = abi.decode(data, (uint256));

        routerV2.unstakeAndRedeemGlp(
            agreement.loans[0].token,
            agreement.collaterals[0].amount,
            minAmountOut,
            address(this)
        );

        uint256 initialBalance = weth.balanceOf(address(this));
        router.handleRewards(false, false, false, false, false, true, false);
        // register rewards
        uint256 finalBalance = weth.balanceOf(address(this));
        uint256 newRewards = totalRewards + (finalBalance - initialBalance);
        // calculate share of rewards to give to the user
        uint256 totalWithdraw = ((newRewards + totalVirtualDeposits) * agreement.collaterals[0].amount) /
            totalCollateral;
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        // Due to integer arithmetic, we may get underflow if we do not make checks
        uint256 toTransfer = totalWithdraw >= virtualDeposit[tokenID]
            ? totalWithdraw - virtualDeposit[tokenID] <= finalBalance
                ? totalWithdraw - virtualDeposit[tokenID]
                : finalBalance
            : 0;
        // delete virtual deposits
        totalVirtualDeposits -= virtualDeposit[tokenID];
        delete virtualDeposit[tokenID];
        // update totalRewards and totalCollateral
        totalRewards = newRewards - toTransfer;
        totalCollateral -= agreement.collaterals[0].amount;
        // Transfer weth: since toTransfer <= totalWithdraw
        weth.safeTransfer(msg.sender, toTransfer);
    }

    function wethReward(uint256 tokenID) public view returns (uint256) {
        uint256 collateral = agreements[tokenID].collaterals[0].amount;
        uint256 newRewards = totalRewards + rewardTracker.claimableReward(address(this));
        // calculate share of rewards to give to the user
        uint256 totalWithdraw = ((newRewards + totalVirtualDeposits) * collateral) / totalCollateral;
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        return totalWithdraw - virtualDeposit[tokenID];
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory results = new uint256[](1);
        uint256 aumInUsdg = glpManager.getAumInUsdg(false);
        uint256 glpSupply = glp.totalSupply();

        if (glpSupply == 0) revert ZeroGlpSupply();
        uint256 usdgAmount = (agreement.collaterals[0].amount * aumInUsdg) / glpSupply;

        uint256 usdgDelta = usdgVault.getRedemptionAmount(agreement.loans[0].token, usdgAmount);

        uint256 feeBasisPoints = usdgVault.getFeeBasisPoints(
            agreement.loans[0].token,
            usdgDelta,
            usdgVault.swapFeeBasisPoints(),
            usdgVault.taxBasisPoints(),
            false
        );
        results[0] = (usdgDelta * (10000 - feeBasisPoints)) / 10000;

        return results;
    }
}
