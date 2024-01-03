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

/// @title    GmxService contract
/// @author   Ithil
/// @dev A service to perform margin trading on the GLP token
/// @custom:security-contact info@ithil.fi
contract GmxService is AuctionRateModel, DebitService {
    using SafeERC20 for IERC20;

    uint256 private constant BASIS_POINTS_DIVISOR = 10000;

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
        if (_manager == address(0)) revert InvalidParams();
        if (_router == address(0)) revert InvalidParams();
        if (_routerV2 == address(0)) revert InvalidParams();

        router = IRewardRouter(_router);
        routerV2 = IRewardRouterV2(_routerV2);
        glp = IERC20(routerV2.glp());
        weth = IERC20(routerV2.weth());

        rewardTracker = IRewardTracker(routerV2.feeGlpTracker());
        glpManager = IGlpManager(routerV2.glpManager());
        usdgVault = IUsdgVault(glpManager.vault());
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        if (agreement.loans.length != 1) revert InvalidParams();
        // First collateral token is GLP
        // Second collateral token is USDG
        // There's no need to specify the collateral tokens since they are enforced in the code
        if (agreement.collaterals.length != 2) revert InvalidParams();

        if (IERC20(agreement.loans[0].token).allowance(address(this), address(glpManager)) == 0) {
            IERC20(agreement.loans[0].token).approve(address(glpManager), type(uint256).max);
        }
        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = routerV2.mintAndStakeGlp(
            agreement.loans[0].token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            agreement.collaterals[1].amount,
            agreement.collaterals[0].amount
        );

        totalCollateral += agreement.collaterals[0].amount;
        if (totalCollateral == 0) revert ZeroGlpSupply();
        // we assign a virtual deposit of v * A / S, __afterwards__ we update the total deposits
        virtualDeposit[id] =
            (agreement.collaterals[0].amount * (totalRewards + totalVirtualDeposits)) /
            totalCollateral;
        totalVirtualDeposits += virtualDeposit[id];
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes memory data) internal override {
        uint256 minAmountOut = abi.decode(data, (uint256));
        uint256 userVirtualDeposit = virtualDeposit[tokenID];
        delete virtualDeposit[tokenID];

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

        uint256 toTransfer = _wethReward(
            agreement.collaterals[0].amount,
            userVirtualDeposit,
            newRewards,
            totalVirtualDeposits,
            totalCollateral,
            finalBalance
        );

        // delete virtual deposits here since _wethReward already subtracts user deposit from total
        totalVirtualDeposits -= userVirtualDeposit;
        // update totalRewards and totalCollateral with an extra check to avoid integer arithmetic underflows
        totalRewards = toTransfer < newRewards ? newRewards - toTransfer : 0;
        totalCollateral -= agreement.collaterals[0].amount;
        // Transfer weth: since toTransfer <= totalWithdraw
        if (toTransfer > 0) weth.safeTransfer(msg.sender, toTransfer);
    }

    function wethReward(uint256 tokenID) public view returns (uint256) {
        uint256 claimableReward = rewardTracker.claimableReward(address(this));
        uint256 finalBalance = weth.balanceOf(address(this)) + claimableReward;
        return
            _wethReward(
                agreements[tokenID].collaterals[0].amount,
                virtualDeposit[tokenID],
                totalRewards + claimableReward,
                totalVirtualDeposits,
                totalCollateral,
                finalBalance
            );
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory) {
        uint256[] memory results = new uint256[](1);
        uint256 aumInUsdg = glpManager.getAumInUsdg(true);
        uint256 glpSupply = glp.totalSupply();

        if (glpSupply == 0) revert ZeroGlpSupply();
        uint256 usdgAmount = (agreement.collaterals[0].amount * aumInUsdg) / glpSupply;

        uint256 redemptionAmount = usdgVault.getRedemptionAmount(agreement.loans[0].token, usdgAmount);

        uint256 feeBasisPoints = usdgVault.getFeeBasisPoints(
            agreement.loans[0].token,
            usdgAmount,
            usdgVault.swapFeeBasisPoints(),
            usdgVault.taxBasisPoints(),
            false
        );
        results[0] = (redemptionAmount * (BASIS_POINTS_DIVISOR - feeBasisPoints)) / BASIS_POINTS_DIVISOR;

        return results;
    }

    function _wethReward(
        uint256 _collateral,
        uint256 _userVirtualDeposit,
        uint256 _totalRewards,
        uint256 _totalVirtualDeposits,
        uint256 _totalCollateral,
        uint256 _finalBalance
    ) internal pure returns (uint256) {
        // calculate share of rewards to give to the user
        uint256 totalWithdraw = ((_totalRewards + _totalVirtualDeposits - _userVirtualDeposit) * _collateral) /
            _totalCollateral;
        return
            // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
            // Due to integer arithmetic, we may get underflow if we do not make checks
            totalWithdraw >= _userVirtualDeposit
                ? totalWithdraw - _userVirtualDeposit <= _finalBalance
                    ? totalWithdraw - _userVirtualDeposit
                    : _finalBalance
                : 0;
    }
}
