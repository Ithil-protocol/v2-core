// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

/// @title Curve and Balancer Gauges
interface IGauge {
    function deposit(uint256 _value) external;

    function withdraw(uint256 _value) external;

    function withdraw(uint256 _value, bool _claim_rewards) external;

    function claim_rewards(address addr) external;

    function claimable_reward(address _addr, address _token) external view returns (uint256);

    function lp_token() external view returns (address);

    function reward_tokens(uint256 index) external view returns (address);
}
