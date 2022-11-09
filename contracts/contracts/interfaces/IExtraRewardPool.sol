// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IExtraRewardPool{
    
    function rewardToken() external view returns(address);
    function pid() external view returns(uint256);
    function periodFinish() external view returns(uint256);
    function rewardRate() external view returns(uint256);
    function totalSupply() external view returns(uint256);
    function balanceOf(address _account) external view returns(uint256);
    
}