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

interface IGlpManager {
    function getAumInUsdg(bool maximise) external view returns (uint256);
    function vault() external view returns (address);
}

interface IUsdgVault {
    function getRedemptionAmount(address _token, uint256 _usdgAmount) external view returns (uint256);
}

/// @title    GmxService contract
/// @author   Ithil
/// @notice   A service to perform margin trading on the GLP token
contract GmxService is SecuritisableService {
    using SafeERC20 for IERC20;

    IRewardRouterV2 public immutable router;
    IERC20 public immutable glp;
    IERC20 public immutable weth;
    IGlpManager public immutable glpManager;
    IUsdgVault public immutable usdgVault;

    constructor(address _manager, address _router)
        Service("GmxService", "GMX-SERVICE", _manager)
    {
        router = IRewardRouterV2(_router);
        glp = IERC20(router.glp());
        weth = IERC20(router.weth());
        glpManager = IGlpManager(router.glpManager());
        usdgVault = IUsdgVault(glpManager.vault());
    }

    function _open(Agreement memory agreement, bytes calldata data) internal override {
        uint256 minGlpOut = abi.decode(data, (uint256));

        address token = agreement.loans[0].token;
        if (IERC20(token).allowance(address(this), address(glpManager)) == 0)
            IERC20(token).safeApprove(address(glpManager), type(uint256).max);

        agreement.collaterals[0].token = address(glp);
        agreement.collaterals[0].amount = router.mintAndStakeGlp(
            token,
            agreement.loans[0].amount + agreement.loans[0].margin,
            0,
            minGlpOut
        );
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes calldata data) internal override {
        uint256 minAmountOut = abi.decode(data, (uint256));

        router.unstakeAndRedeemGlp(
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
        uint256 usdgAmount = agreement.collaterals[0].amount * aumInUsdg / glpSupply;
        results[0] = usdgVault.getRedemptionAmount(agreement.loans[0].token, usdgAmount);
    }
}
