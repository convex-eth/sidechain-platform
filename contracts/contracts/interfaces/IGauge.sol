// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IGauge {
    function deposit(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
    function claim_rewards() external;
    function claim_rewards(address _account) external;
    function reward_tokens(uint256) external view returns(address);//v2
    function rewarded_token() external view returns(address);//v1
    function lp_token() external view returns(address);
    function set_rewards_receiver(address _receiver) external;
    function claimed_reward(address _account, address _token) external view returns(uint256);
    function claimable_reward(address _account, address _token) external view returns(uint256);
    function claimable_reward_write(address _account, address _token) external returns(uint256);
}