// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

/// @title    Interface of the Convex base reward contract
interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    function withdrawAllAndUnwrap(bool claim) external;

    function getReward() external returns (bool);

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function earned(address) external view returns (uint256);

    function stake(uint256 _amount) external returns (bool);

    function stakeAll() external returns (bool);

    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 i) external view returns (address);
}
