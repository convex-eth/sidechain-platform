// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IGauge.sol";
import "./interfaces/IStash.sol";
import "./interfaces/IDeposit.sol";
import "./interfaces/IRewardHook.sol";

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


//claim and distribute gauge rewards without need of harvesters
//more gas cost but no delayed rewards
contract ConvexRewardPool {
    using SafeERC20 for IERC20;

    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct RewardType {
        address reward_token;
        uint128 reward_integral;
        uint128 reward_remaining;
    }

    //supply and balances
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    //pool and system info
    address public curveGauge;
    address public convexStaker;
    address public convexBooster;
    address public convexToken;
    uint256 public convexPoolId;


    //rewards
    RewardType[] public rewards;
    mapping(address => mapping(address => uint256)) public reward_integral_for;
    mapping(address => mapping(address => uint256)) public claimable_reward;
    mapping(address => bool) public rewardMap;
    address public rewardHook;
    address public crv;

    //management
    bool public isInit;

    //events
    event Staked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event RewardPaid(address indexed _user, address indexed _rewardToken, address indexed _receiver, uint256 _rewardAmount);
    event RewardAdded(address indexed _rewardToken);

    constructor(){}

    function initialize(
        address _crv,
        address _curveGauge,
        address _convexStaker,
        address _convexBooster,
        address _convexToken,
        uint256 _poolId)
    external {
        require(!isInit,"already init");

        isInit = true;
        crv = _crv;
        curveGauge = _curveGauge;
        convexStaker = _convexStaker;
        convexBooster = _convexBooster;
        convexToken = _convexToken;
        convexPoolId = _poolId;

        _insertRewardToken(_crv);
    }

    function updateRewardList() public {

        //max rewards 8, need to check if anything new has been added
        for (uint256 i = 0; i < 8; i++) {
            address rewardToken = IGauge(curveGauge).reward_tokens(i);
            if(rewardToken == address(0)) break;

            //add to reward list if new
            _insertRewardToken(rewardToken);
        }
    }

    //register an extra reward token to be handled
    // (any new incentive that is not directly on curve gauges)
    function setExtraReward(address _token) external{
        //owner of booster can set extra rewards
        require(IDeposit(convexBooster).owner() == msg.sender, "!owner");
        
        //add to reward list
        _insertRewardToken(_token);
    }

    function _insertRewardToken(address _token) internal{
        //add to reward list if new
        if(!rewardMap[_token]){
            RewardType storage r = rewards.push();
            r.reward_token = _token;
            rewardMap[_token] = true;
            emit RewardAdded(_token);
        }
    }

    function setRewardHook(address _hook) external{
        //owner of booster can set reward hook
        require(IDeposit(convexBooster).owner() == msg.sender, "!owner");
        rewardHook = _hook;
    }

    function updateRewardsAndClaim() internal{
        //make sure reward list is up to date
        updateRewardList();

        //claim crv
        IDeposit(convexBooster).claimCrv(convexPoolId, curveGauge);

        //claim rewards from gauge
        IGauge(curveGauge).claim_rewards(convexStaker);

        //hook for reward pulls
        if(rewardHook != address(0)){
            try IRewardHook(rewardHook).onRewardClaim(){
            }catch{}
        }
    }

    function rewardLength() external view returns(uint256) {
        return rewards.length;
    }

    function _calcRewardIntegral(uint256 _index, address _account, address _forwardTo) internal{
        RewardType storage reward = rewards[_index];

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));

        //if reward token is crv, need to calculate fees
        if(reward.reward_token == crv){
            uint256 diff = bal - reward.reward_remaining;
            uint256 fees = IDeposit(convexBooster).calculatePlatformFees(diff);
            if(fees > 0){
                //send to booster to process later
                IERC20(crv).safeTransfer(convexBooster, fees);
            }
            bal -= fees;
        }

        if (_totalSupply > 0 && (bal - reward.reward_remaining) > 0) {
            reward.reward_integral = reward.reward_integral + uint128( (bal - reward.reward_remaining) * 1e20 / _totalSupply);
        }

        //update user integrals
        // uint userI = reward.reward_integral_for[_account];
        uint userI = reward_integral_for[reward.reward_token][_account];
        if(_forwardTo != address(0) || userI < reward.reward_integral){
            //forward to address non-zero means its a claim 
            if(_forwardTo != address(0)){
                uint256 receiveable = claimable_reward[reward.reward_token][_account] + (_balances[_account] * uint256(reward.reward_integral - userI) / 1e20);
                if(receiveable > 0){
                    claimable_reward[reward.reward_token][_account] = 0;
                    IERC20(reward.reward_token).safeTransfer(_forwardTo, receiveable);
                    emit RewardPaid(_account, reward.reward_token, _forwardTo, receiveable);
                    bal -= receiveable;
                }
            }else{
                claimable_reward[reward.reward_token][_account] = claimable_reward[reward.reward_token][_account] + ( _balances[_account] * uint256(reward.reward_integral - userI) / 1e20);
            }
            reward_integral_for[reward.reward_token][_account] = reward.reward_integral;
        }


        //update remaining reward here since balance could have changed if claiming
        if(bal !=  reward.reward_remaining){
            reward.reward_remaining = uint128(bal);
        }
    }

    function _checkpoint(address _account) internal {
        //update rewards and claim
        updateRewardsAndClaim();

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
           _calcRewardIntegral(i,_account,address(0));
        }
    }

    function _checkpointAndClaim(address _account, address _forwardTo) internal {
        //update rewards and claim
        updateRewardsAndClaim();

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
           _calcRewardIntegral(i,_account,_forwardTo);
        }
    }

    function user_checkpoint(address _account) external returns(bool) {
        _checkpoint(_account);
        return true;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    //get earned token info
    //Note: The curve gauge function "claimable_tokens" is a write function and thus this is not by default a view
    //change ABI to view to use this off chain
    function earned(address _account) external returns(EarnedData[] memory claimable) {

        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            //change in reward is current balance - remaining reward + earned
            uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
            uint256 d_reward = bal - reward.reward_remaining;
            // crv is always slot 0. while unlikely, if crv was also added as a reward token checking by address would cause it to be skipped
            if(i == 0){
                uint256 camount = IGauge(curveGauge).claimable_tokens(convexStaker);
                uint256 fees = IDeposit(convexBooster).calculatePlatformFees(camount);
                if(fees > 0){
                    camount -= fees;
                }
                d_reward = d_reward + camount;
            }else{
                d_reward = d_reward + IGauge(curveGauge).claimable_reward(convexStaker, reward.reward_token);
            }

            uint256 I = reward.reward_integral;
            if (_totalSupply > 0) {
                I = I + (d_reward * 1e20 / _totalSupply);
            }

            uint256 newlyClaimable = _balances[_account] * (I - reward_integral_for[reward.reward_token][_account]) / 1e20;
            claimable[i].amount = claimable_reward[reward.reward_token][_account] + newlyClaimable;
            claimable[i].token = reward.reward_token;
        }
        return claimable;
    }

    //claim reward for given account (unguarded)
    function getReward(address _account) external {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpointAndClaim(_account, _account);
    }

    //claim reward for given account and forward (guarded)
    function getReward(address _account, address _forwardTo) external {
        require(msg.sender == _account, "!self");
        //claim directly in checkpoint logic to save a bit of gas
        //pack forwardTo into account array to save gas so that a proxy etc doesnt have to double transfer
        _checkpointAndClaim(_account,_forwardTo);
    }

    //Deposit/Stake

    function stake(uint256 _amount) public returns(bool){
        require(_amount > 0, 'RewardPool : Cannot stake 0');
        
        _checkpoint(msg.sender);

        _totalSupply += _amount;
        _balances[msg.sender] += _amount;

        IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        emit Staked(msg.sender, _amount);

        return true;
    }

    function stakeAll() external returns(bool){
        uint256 balance = IERC20(convexToken).balanceOf(msg.sender);
        stake(balance);
        return true;
    }

    function stakeFor(address _for, uint256 _amount) public returns(bool){
        require(_amount > 0, 'RewardPool : Cannot stake 0');
        
        _checkpoint(_for);

        //give to _for
        _totalSupply += _amount;
        _balances[_for] += _amount;

        //take away from sender
        IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        emit Staked(_for, _amount);
        
        return true;
    }

    //Withdraw

    function withdraw(uint256 amount, bool claim) public returns(bool){
        require(amount > 0, 'RewardPool : Cannot withdraw 0');

        if(claim){
            _checkpointAndClaim(msg.sender, msg.sender);
        }else{
            _checkpoint(msg.sender);
        }

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        IERC20(convexToken).safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
     
        return true;
    }

    function withdrawAll(bool claim) external{
        withdraw(_balances[msg.sender],claim);
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) public returns(bool){

        if(claim){
            _checkpointAndClaim(msg.sender, msg.sender);
        }else{
            _checkpoint(msg.sender);
        }
        
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        //tell convexBooster to withdraw from here directly to user
        IDeposit(convexBooster).withdrawTo(convexPoolId,amount,msg.sender);

        emit Withdrawn(msg.sender, amount);

        return true;
    }

    function withdrawAllAndUnwrap(bool claim) external{
        withdrawAndUnwrap(_balances[msg.sender],claim);
    }

}