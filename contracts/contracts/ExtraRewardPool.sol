// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
/**
 *Submitted for verification at Etherscan.io on 2020-07-17
 */

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Synthetix: BaseRewardPool.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "./interfaces/MathUtil.sol";
import "./interfaces/IDeposit.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


/*
 Reward contract managed by a RewardManager which can manually set weights for any account address
*/
contract ExtraRewardPool {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public constant duration = 7 days;

    address public immutable booster;

    uint256 public pid;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards;
    uint256 public currentRewards;
    uint256 public historicalRewards;
    
    uint256 private _totalSupply;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;

    event RewardAdded(uint256 reward);
    event WeightSet(address indexed user, uint256 oldWeight, uint256 newWeight);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _booster){
        booster = _booster;
    }

    function initialize(
        address rewardToken_
    ) external {
        require(address(rewardToken) == address(0),"already init");

        rewardToken = IERC20(rewardToken_);
    }

    function rewardManager() public view returns(address){
        return IDeposit(booster).rewardManager();
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _account) public view returns (uint256) {
        return _balances[_account];
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    function user_checkpoint(address _account) public updateReward(_account){

    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return MathUtil.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply());
    }

    function earned(address _account) public view returns (uint256) {
        return rewards[_account] + (balanceOf(_account) * (rewardPerToken() - userRewardPerTokenPaid[_account]) / 1e18);
    }


    //increase reward weight for a  given pool
    //used by reward manager
    function setWeight(address _account, uint256 _amount)
        public
        updateReward(_account)
        returns(bool)
    {
        require(msg.sender == rewardManager(), "!authorized");

        emit WeightSet(_account, _balances[_account], _amount);

        uint256 tsupply = _totalSupply;
        tsupply -= _balances[_account]; //remove current
        _balances[_account] = _amount; //set new
        tsupply += _amount; //add new to supply
        _totalSupply = tsupply; //set supply

        //work around to correct earned() function on ConvexRewardPool for a new reward type
        rewardToken.safeTransfer(_account, 0);
        return true;
    }

    function getReward(address _account) public updateReward(_account) returns(bool){
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            rewardToken.safeTransfer(_account, reward);
            emit RewardPaid(_account, reward);
        }
        return true;
    }

    function donate(uint256 _amount) external returns(bool){
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        queuedRewards += _amount;
        return true;
    }

    function queueNewRewards(uint256 _rewards) external returns(bool){
        require(msg.sender == rewardManager(), "!authorized");

        notifyRewardAmount(_rewards + queuedRewards);
        queuedRewards = 0;
        return true;
    }


    function notifyRewardAmount(uint256 reward)
        internal
        updateReward(address(0))
    {
        historicalRewards += reward;
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward += leftover;
            rewardRate = reward / duration;
        }
        currentRewards = reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }
}