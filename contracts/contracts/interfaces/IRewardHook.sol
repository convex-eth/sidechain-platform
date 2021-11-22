// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardHook {
    function onRewardClaim() external;
}