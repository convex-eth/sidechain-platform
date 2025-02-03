// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IGaugeOther {
    function deposit(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function working_balances(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function working_supply() external view returns (uint256);
    function withdraw(uint256) external;
    function claim_rewards() external;
    function claim_rewards(address _account) external;
    function lp_token() external view returns(address);
    function set_rewards_receiver(address _receiver) external;
    function reward_count() external view returns(uint256);
    function reward_tokens(uint256 _rid) external view returns(address _rewardToken);
    function reward_data(address _reward) external view returns(address distributor, uint256 period_finish, uint256 rate, uint256 last_update, uint256 integral);
    function claimed_reward(address _account, address _token) external view returns(uint256);
    function claimable_reward(address _account, address _token) external view returns(uint256);
    function claimable_tokens(address _account) external returns(uint256);
    function inflation_rate(uint256 _week) external view returns(uint256);
    function period() external view returns(int128);
    function period_timestamp(int128 _period) external view returns(uint256);
    // function claimable_reward_write(address _account, address _token) external returns(uint256);
    function add_reward(address _reward, address _distributor) external;
    function set_reward_distributor(address _reward, address _distributor) external;
    function deposit_reward_token(address _reward, uint256 _amount) external;
    function manager() external view returns(address _manager);
}