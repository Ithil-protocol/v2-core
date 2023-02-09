// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17;

interface IMiniChef {
    function SUSHI() external view returns (address);

    function harvest(uint256 _pid, address to) external;

    function deposit(uint256 _pid, uint256 _amount, address to) external;

    function withdraw(uint256 _pid, uint256 _amount, address to) external;

    function emergencyWithdraw(uint256 _pid, address to) external;

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

    function userInfo(uint256 _pid, address _user) external view returns (uint256, int256);

    function poolInfo(uint256 _pid) external view returns (uint128, uint64, uint64);

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function sushiPerSecond() external view returns (uint256);
}
