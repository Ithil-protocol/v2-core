// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

interface IRewardRouter {
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

interface IRewardRouterV2 {
    function glp() external view returns (address);

    function stakeGmx(uint256 _amount) external;

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable returns (uint256);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);

    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    function signalTransfer(address _receiver) external;

    function acceptTransfer(address _sender) external;

    function pendingReceivers(address _sender) external returns (address);

    function weth() external view returns (address);

    function gmx() external view returns (address);

    function bnGmx() external view returns (address);

    function esGmx() external view returns (address);

    function feeGmxTracker() external view returns (address);

    function feeGlpTracker() external view returns (address);

    function stakedGlpTracker() external view returns (address);

    function stakedGmxTracker() external view returns (address);

    function bonusGmxTracker() external view returns (address);

    function glpManager() external view returns (address);
}

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

    function claimableReward(address _account) external view returns (uint256);

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

    function swapFeeBasisPoints() external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);
}
