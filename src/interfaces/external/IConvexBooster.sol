// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

/// @title    Interface of the Convex boosted rewards contract
interface IConvexBooster {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);

    function crv() external view returns (address);
}
