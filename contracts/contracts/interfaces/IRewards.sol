// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewards{
    function stake(address, uint256) external;
    function stakeFor(address, uint256) external;
    function withdraw(address, uint256) external;
    function setWeight(address _pool, uint256 _amount) external returns(bool);
    function exit(address) external;
    function getReward(address) external;
    function queueNewRewards(uint256) external;
    function notifyRewardAmount(uint256) external;
    function addExtraReward(address) external;
    function setRewardHook(address) external;
    function stakingToken() external view returns (address);
    function rewardToken() external view returns(address);
    function rewardMap(address) external view returns(bool);
    function earned(address account) external view returns (uint256);
}