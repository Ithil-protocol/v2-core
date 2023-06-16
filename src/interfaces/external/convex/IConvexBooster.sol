// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

/// @title    Interface of the Convex boosted rewards contract
interface IConvexBooster {
    struct PoolInfo {
        address lptoken; //the curve lp token
        address gauge; //the curve gauge
        address rewards; //the main reward/staking contract
        bool shutdown; //is this pool shutdown?
        address factory; //a reference to the curve factory used to create this pool (needed for minting crv)
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function deposit(uint256 _pid, uint256 _amount) external returns (bool);

    function depositAll(uint256 _pid) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);
}
