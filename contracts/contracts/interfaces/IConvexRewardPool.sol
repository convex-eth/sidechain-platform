// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IConvexRewardPool{
    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct RewardType {
        address reward_token;
        uint128 reward_integral;
        uint128 reward_remaining;
    }

    function initialize(
        address _crv,
        address _curveGauge,
        address _convexStaker,
        address _convexBooster,
        address _convexToken,
        uint256 _poolId) external;
    function setExtraReward(address) external;
    function setRewardHook(address) external;
    function getReward(address) external;
    function user_checkpoint(address) external;
    function rewardLength() external returns(uint256);
    function totalSupply() external returns(uint256);
    function balanceOf(address) external returns(uint256);
    function rewards(uint256 _rewardIndex) external returns(RewardType memory);
    function earnedView(address _account) external view returns(EarnedData[] memory claimable);
    function earned(address _account) external returns(EarnedData[] memory claimable);
    function stakeFor(address _for, uint256 _amount) external returns(bool);
    function withdraw(uint256 amount, bool claim) external returns(bool);
    function withdrawAll(bool claim) external;
}