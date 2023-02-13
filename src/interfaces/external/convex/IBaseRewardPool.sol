// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

/// @title    Interface of the Convex base reward contract
interface IBaseRewardPool {
    function withdraw(uint256 amount, bool claim) external returns (bool);

    function withdrawAll(bool claim) external;

    function getReward(address _account) external;

    function balanceOf(address) external view returns (uint256);

    function earned(address) external view returns (uint256);

    function stake(uint256 _amount) external returns (bool);

    function stakeAll() external returns (bool);
}
