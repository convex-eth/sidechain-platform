// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IGauge.sol";
import "./interfaces/IBooster.sol";
import "./interfaces/IRewardHook.sol";
import "./interfaces/IRewardManager.sol";

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


//claim and distribute gauge rewards without need of harvesters
//more gas cost but no delayed rewards
//
//Reward distro based on Curve.fi's gauge wrapper implementations at https://github.com/curvefi/curve-dao-contracts/tree/master/contracts/gauges/wrappers
contract ConvexRewardPool is ReentrancyGuard{
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
    mapping(address => mapping(address => uint256)) public reward_integral_for;// token -> account -> integral
    mapping(address => mapping(address => uint256)) public claimable_reward;//token -> account -> claimable
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

        //always add CRV in first slot
        _insertRewardToken(_crv);

        //add CVX in second slot
        address rmanager = IBooster(convexBooster).rewardManager();
        _insertRewardToken(IRewardManager(rmanager).cvx());

        //set default hook
        rewardHook = IRewardManager(rmanager).rewardHook();
    }

    //check curve gauge for any reward tokens
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
    function addExtraReward(address _token) external{
        //reward manager can set extra rewards
        require(IBooster(convexBooster).rewardManager() == msg.sender, "!owner");
        
        //add to reward list
        _insertRewardToken(_token);
    }

    //insert a new reward, ignore if already registered or invalid
    function _insertRewardToken(address _token) internal{
        if(_token == convexToken || _token == address(0)){
            //dont allow reward tracking of the staking token or invalid address
            return;
        }
        //add to reward list if new
        if(!rewardMap[_token]){
            RewardType storage r = rewards.push();
            r.reward_token = _token;
            rewardMap[_token] = true;

            //workaround: transfer 0 to self so that earned() reports correctly
            //with new tokens
            try IERC20(_token).transfer(address(this), 0){}catch{}

            emit RewardAdded(_token);
        }
    }

    //set a reward hook that calls an outside contract to pull external rewards
    function setRewardHook(address _hook) external{
        //reward manager can set reward hook
        require(IBooster(convexBooster).rewardManager() == msg.sender, "!owner");
        rewardHook = _hook;
    }

    //update and claim rewards from all locations
    function updateRewardsAndClaim() internal{
        //make sure reward list is up to date
        updateRewardList();

        //claim crv
        IBooster(convexBooster).claimCrv(convexPoolId, curveGauge);

        //claim rewards from gauge
        IGauge(curveGauge).claim_rewards(convexStaker);

        //hook for external reward pulls
        if(rewardHook != address(0)){
            try IRewardHook(rewardHook).onRewardClaim(){
            }catch{}
        }
    }

    //get reward count
    function rewardLength() external view returns(uint256) {
        return rewards.length;
    }

    //calculate and record an account's earnings of the given reward.  if _claimTo is given it will also claim.
    function _calcRewardIntegral(uint256 _index, address _account, address _claimTo) internal{
        RewardType storage reward = rewards[_index];

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed since last checkpoint
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));

        //if reward token is crv (always slot 0), need to calculate and send fees
        if(_index == 0){
            uint256 diff = bal - reward.reward_remaining;
            uint256 fees = IBooster(convexBooster).calculatePlatformFees(diff);
            if(fees > 0){
                //send to fee deposit to process later
                IERC20(crv).safeTransfer( IBooster(convexBooster).feeDeposit() , fees);
            }
            //remove what was sent as fees
            bal -= fees;
        }

        //update the global integral
        if (_totalSupply > 0 && (bal - reward.reward_remaining) > 0) {
            reward.reward_integral = reward.reward_integral + uint128( (bal - reward.reward_remaining) * 1e20 / _totalSupply);
        }

        //update user integrals
        uint userI = reward_integral_for[reward.reward_token][_account];
        if(_claimTo != address(0) || userI < reward.reward_integral){
            //_claimTo address non-zero means its a claim 
            if(_claimTo != address(0)){
                uint256 receiveable = claimable_reward[reward.reward_token][_account] + (_balances[_account] * uint256(reward.reward_integral - userI) / 1e20);
                if(receiveable > 0){
                    claimable_reward[reward.reward_token][_account] = 0;
                    IERC20(reward.reward_token).safeTransfer(_claimTo, receiveable);
                    emit RewardPaid(_account, reward.reward_token, _claimTo, receiveable);
                    //remove what was claimed from balance
                    bal -= receiveable;
                }
            }else{
                claimable_reward[reward.reward_token][_account] = claimable_reward[reward.reward_token][_account] + ( _balances[_account] * uint256(reward.reward_integral - userI) / 1e20);
            }
            reward_integral_for[reward.reward_token][_account] = reward.reward_integral;
        }


        //update remaining reward so that next claim can properly calculate the balance change
        if(bal != reward.reward_remaining){
            reward.reward_remaining = uint128(bal);
        }
    }

    //checkpoint without claiming
    function _checkpoint(address _account) internal {
        //checkpoint without claiming by passing address(0)
        _checkpoint(_account, address(0));
    }

    //checkpoint with claim
    function _checkpoint(address _account, address _claimTo) internal {
        //update rewards and claim
        updateRewardsAndClaim();

        //calc reward integrals
        uint256 rewardCount = rewards.length;
        for(uint256 i = 0; i < rewardCount; i++){
           _calcRewardIntegral(i,_account,_claimTo);
        }
    }

    //manually checkpoint a user account
    function user_checkpoint(address _account) external nonReentrant returns(bool) {
        _checkpoint(_account);
        return true;
    }

    //get total supply
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    //get balance of a user account
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }


    //get earned token info
    //Note: The curve gauge function "claimable_tokens" is a write function and thus this is not by default a view
    //change ABI to view to use this off chain
    function earned(address _account) external returns(EarnedData[] memory claimable) {
        
        //because this is a state mutative function
        //we can simplify the earned() logic of all rewards (internal and external)
        //and allow this contract to be agnostic to outside reward contract design
        //by just claiming everything and checking token balances
        updateRewardsAndClaim();

        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            //change in reward is current balance - remaining reward + earned
            uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));
            uint256 d_reward = bal - reward.reward_remaining;

            // crv is always slot 0
            if(i == 0){
                //check fees
                uint256 fees = IBooster(convexBooster).calculatePlatformFees(d_reward);
                if(fees > 0){
                    d_reward -= fees;
                }
            }

            //calc new global integral
            uint256 I = reward.reward_integral;
            if (_totalSupply > 0) {
                I = I + (d_reward * 1e20 / _totalSupply);
            }

            //user claimable amount = previous recorded claimable + new user integral
            uint256 newlyClaimable = _balances[_account] * (I - reward_integral_for[reward.reward_token][_account]) / 1e20;
            claimable[i].amount = claimable_reward[reward.reward_token][_account] + newlyClaimable;
            claimable[i].token = reward.reward_token;
        }
    }

    //claim reward for given account (unguarded)
    function getReward(address _account) external nonReentrant {
        //claim directly in checkpoint logic to save a bit of gas
        _checkpoint(_account, _account);
    }

    //claim reward for given account and forward (guarded)
    function getReward(address _account, address _forwardTo) external nonReentrant {
        //in order to forward, must be called by the account itself
        require(msg.sender == _account, "!self");
        //use _forwardTo address instead of _account
        _checkpoint(_account,_forwardTo);
    }

    //Deposit/Stake a given amount
    function stake(uint256 _amount) public nonReentrant returns(bool){
        require(_amount > 0, 'RewardPool : Cannot stake 0');
        
        //checkpoint first
        _checkpoint(msg.sender);

        //change state
        _totalSupply += _amount;
        _balances[msg.sender] += _amount;

        //pull tokens
        IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        emit Staked(msg.sender, _amount);

        return true;
    }

    //stake/deposit entire balance
    function stakeAll() external returns(bool){
        uint256 balance = IERC20(convexToken).balanceOf(msg.sender);
        stake(balance);
        return true;
    }

    //deposit/stake on behalf of another account
    function stakeFor(address _for, uint256 _amount) external nonReentrant returns(bool){
        require(_amount > 0, 'RewardPool : Cannot stake 0');
        
        //checkpoint first
        _checkpoint(_for);

        //change state
        //assign to _for
        _totalSupply += _amount;
        _balances[_for] += _amount;

        //pull tokens from sender
        IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        emit Staked(_for, _amount);
        
        return true;
    }

    //Withdraw a given amount. Can choose not to claim
    function withdraw(uint256 amount, bool claim) public nonReentrant returns(bool){
        require(amount > 0, 'RewardPool : Cannot withdraw 0');

        //checkpoint first, if claim add claim address
        _checkpoint(msg.sender, claim ? msg.sender : address(0));

        //change state
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        //transfer tokens
        IERC20(convexToken).safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
     
        return true;
    }

    //withdraw full balance
    function withdrawAll(bool claim) external{
        withdraw(_balances[msg.sender],claim);
    }

    //withdraw balance and unwrap to the underlying lp token
    function withdrawAndUnwrap(uint256 amount, bool claim) public nonReentrant returns(bool){

        //checkpoint first, if claim add claim address
        _checkpoint(msg.sender, claim ? msg.sender : address(0));
        
        //change state
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        //tell booster to withdraw underlying lp tokens directly to user
        //booster will burn the tokens, thus no transfer is needed
        IBooster(convexBooster).withdrawTo(convexPoolId,amount,msg.sender);

        emit Withdrawn(msg.sender, amount);

        return true;
    }

    //withdraw full balance and unwrap to the underlying lp token
    function withdrawAllAndUnwrap(bool claim) external{
        withdrawAndUnwrap(_balances[msg.sender],claim);
    }

}