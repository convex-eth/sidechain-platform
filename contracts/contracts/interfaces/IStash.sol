// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IStash{
    function stashRewards() external returns (bool);
    function processStash() external returns (bool);
    function claimRewards() external returns (bool);
    function rewardCount() external view returns (uint256);
    function rewardList(uint256 _index) external view returns(address);
    function pullReward(address _token) external;
    function initialize(uint256 _pid, address _operator, address _staker, address _gauge, address _rewardFactory) external;
}