// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardFactory{
    function CreateMainRewards(address _crv, address _gauge, address _depositToken, uint256 _pid) external returns (address);
}