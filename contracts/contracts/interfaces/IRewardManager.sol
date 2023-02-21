// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardManager {
    function rewardHook() external view returns(address);
    function cvx() external view returns(address);
    function setPoolRewardToken(address _pool, address _token) external;
    function setPoolRewardContract(address _pool, address _hook, address _token) external;
}