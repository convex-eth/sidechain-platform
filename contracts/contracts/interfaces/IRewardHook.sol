// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardHook {
    function onRewardClaim() external;
    function rewardManager() external view returns(address);
    function poolRewardLength(address _pool) external view returns(uint256);
    function clearPoolRewardList(address _pool) external;
    function addPoolReward(address _pool, address _rewardContract) external;
}