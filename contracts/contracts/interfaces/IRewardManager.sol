// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardManager {
    function rewardHook() external view returns(address);
}