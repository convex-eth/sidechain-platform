// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IConvexRewardPool.sol";
import "../interfaces/IBooster.sol";
import "../interfaces/IRewardHook.sol";
import "../interfaces/IERC4626.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


//Example of a tokenize a convex staked position.
//if used as collateral some modifications will be needed to fit the specific platform

//Based on Curve.fi's gauge wrapper implementations at https://github.com/curvefi/curve-dao-contracts/tree/master/contracts/gauges/wrappers
contract ConvexStakingWrapper is ERC20, IERC4626, ReentrancyGuard {
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
    mapping(address => mapping(address => uint256)) public reward_integral_for;// token -> account -> integral
    mapping(address => mapping(address => uint256)) public claimable_reward;//token -> account -> claimable

    //constants/immutables
    address public immutable convexBooster;
    address public immutable crv;
    address public immutable cvx;
    address public curveToken;
    address public convexPool;
    uint256 public convexPoolId;
    address public collateralVault;
    uint256 private constant CRV_INDEX = 0;
    uint256 private constant CVX_INDEX = 1;

    //rewards
    RewardType[] public rewards;
    mapping(address => uint256) public registeredRewards;
    address public rewardHook;
    mapping(address => address) public rewardRedirect;

    //management
    bool public isShutdown;
    bool public isInit;
    address public owner;

    string internal _tokenname;
    string internal _tokensymbol;

    event Deposited(address indexed _user, address indexed _account, uint256 _amount, bool _wrapped);
    event Withdrawn(address indexed _user, uint256 _amount, bool _unwrapped);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardInvalidated(address _rewardToken);
    event RewardRedirected(address indexed _account, address _forward);
    event RewardAdded(address _token);
    event Shutdown();
    event HookSet(address _hook);
    event UserCheckpoint(address _userA, address _userB);

    constructor(address _booster, address _crv, address _cvx)
        ERC20(
            "StakedConvexToken",
            "stkCvx"
        ){
        convexBooster = _booster;
        crv = _crv;
        cvx = _cvx;
    }

    function initialize(uint256 _poolId)
    virtual external {
        require(!isInit,"already init");
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);

        (address _lptoken, , address _rewards, , ) = IBooster(convexBooster).poolInfo(_poolId);
        curveToken = _lptoken;
        convexPool = _rewards;
        convexPoolId = _poolId;

        _tokenname = string(abi.encodePacked("Wrapped ", ERC20(_rewards).name() ));
        _tokensymbol = string(abi.encodePacked("w", ERC20(_rewards).symbol()));
        isShutdown = false;
        isInit = true;

        // collateralVault = _vault;

        //add rewards
        addRewards();
        setApprovals();
    }

    function name() public view override returns (string memory) {
        return _tokenname;
    }

    function symbol() public view override returns (string memory) {
        return _tokensymbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function shutdown() external onlyOwner {
        isShutdown = true;
        emit Shutdown();
    }

    function setApprovals() public {
        IERC20(curveToken).safeApprove(convexBooster, 0);
        IERC20(curveToken).safeApprove(convexBooster, type(uint256).max);
    }

    function addRewards() public {
        address mainPool = convexPool;

        if (rewards.length == 0) {
            rewards.push(
                RewardType({
                    reward_token: crv,
                    reward_integral: 0,
                    reward_remaining: 0
                })
            );
            rewards.push(
                RewardType({
                    reward_token: cvx,
                    reward_integral: 0,
                    reward_remaining: 0
                })
            );
            registeredRewards[crv] = CRV_INDEX+1; //mark registered at index+1
            registeredRewards[cvx] = CVX_INDEX+1; //mark registered at index+1
            //send to self to warmup state
            IERC20(crv).transfer(address(this),0);
            //send to self to warmup state
            IERC20(cvx).transfer(address(this),0);
            emit RewardAdded(crv);
            emit RewardAdded(cvx);
        }

        uint256 rewardCount = IConvexRewardPool(mainPool).rewardLength();
        for (uint256 i = 0; i < rewardCount; i++) {

            // (address rewardToken,,) = IConvexRewardPool(mainPool).rewards(i);
            IConvexRewardPool.RewardType memory rewardType = IConvexRewardPool(mainPool).rewards(i);
            if(registeredRewards[rewardType.reward_token] == 0){
                //add new token to list
                rewards.push(
                    RewardType({
                        reward_token: rewardType.reward_token,
                        reward_integral: 0,
                        reward_remaining: 0
                    })
                );
                registeredRewards[rewardType.reward_token] = rewards.length; //mark registered at index+1
                emit RewardAdded(rewardType.reward_token);
            }
        }
    }

    function addTokenReward(address _token) public onlyOwner {

        //check if already registered
        if(registeredRewards[_token] == 0){
            //add new token to list
            rewards.push(
                RewardType({
                    reward_token: _token,
                    reward_integral: 0,
                    reward_remaining: 0
                })
            );
            //add to registered map
            registeredRewards[_token] = rewards.length; //mark registered at index+1
            //send to self to warmup state
            IERC20(_token).transfer(address(this),0);   
            emit RewardAdded(_token);
        }else{
            //get previous used index of given token
            //this ensures that reviving can only be done on the previous used slot
            uint256 index = registeredRewards[_token];
            //index is registeredRewards minus one
            RewardType storage reward = rewards[index-1];
            //check if it was invalidated
            if(reward.reward_token == address(0)){
                //revive
                reward.reward_token = _token;
                emit RewardAdded(_token);
            }
        }
    }

    //allow invalidating a reward if the token causes trouble in calcRewardIntegral
    function invalidateReward(address _token) public onlyOwner {
        uint256 index = registeredRewards[_token];
        if(index > 0){
            //index is registered rewards minus one
            RewardType storage reward = rewards[index-1];
            require(reward.reward_token == _token, "!mismatch");
            //set reward token address to 0, integral calc will now skip
            reward.reward_token = address(0);
            emit RewardInvalidated(_token);
        }
    }

    function setHook(address _hook) external onlyOwner{
        rewardHook = _hook;
        emit HookSet(_hook);
    }

    function rewardLength() external view returns(uint256) {
        return rewards.length;
    }

    function _getDepositedBalance(address _account) internal virtual view returns(uint256) {
        if (_account == address(0) || _account == collateralVault) {
            return 0;
        }
        //get balance from collateralVault

        return balanceOf(_account);
    }

    function _getTotalSupply() internal virtual view returns(uint256){

        //override and add any supply needed (interest based growth)

        return totalSupply();
    }

    function _calcRewardIntegral(uint256 _index, address[2] memory _accounts, uint256[2] memory _balances, uint256 _supply, bool _isClaim) internal{
         RewardType storage reward = rewards[_index];
         if(reward.reward_token == address(0)){
            return;
         }

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));

        if (_supply > 0 && (bal - reward.reward_remaining) > 0) {
            reward.reward_integral = reward.reward_integral + uint128( (bal - reward.reward_remaining) * 1e20 / _supply);
        }

        //update user integrals
        for (uint256 u = 0; u < _accounts.length; u++) {
            //do not give rewards to address 0
            if (_accounts[u] == address(0)) continue;
            if (_accounts[u] == collateralVault) continue;
            if(_isClaim && u != 0) continue; //only update/claim for first address and use second as forwarding

            uint userI = reward_integral_for[reward.reward_token][_accounts[u]];
            if(_isClaim || userI < reward.reward_integral){
                if(_isClaim){
                    uint256 receiveable = claimable_reward[reward.reward_token][_accounts[u]] + (_balances[u] * uint256(reward.reward_integral - userI) / 1e20);
                    if(receiveable > 0){
                        claimable_reward[reward.reward_token][_accounts[u]] = 0;
                        //cheat for gas savings by transfering to the second index in accounts list
                        //if claiming only the 0 index will update so 1 index can hold forwarding info
                        //guaranteed to have an address in u+1 so no need to check
                        IERC20(reward.reward_token).safeTransfer(_accounts[u+1], receiveable);
                        bal -= receiveable;
                    }
                }else{
                    claimable_reward[reward.reward_token][_accounts[u]] = claimable_reward[reward.reward_token][_accounts[u]] + ( _balances[u] * uint256(reward.reward_integral - userI) / 1e20);
            }
                reward_integral_for[reward.reward_token][_accounts[u]] = reward.reward_integral;
            }
        }

        //update remaining reward here since balance could have changed if claiming
        if(bal != reward.reward_remaining){
            reward.reward_remaining = uint128(bal);
        }
    }

    function _checkpoint(address[2] memory _accounts) internal nonReentrant{
        uint256 supply = _getTotalSupply();
        uint256[2] memory depositedBalance;
        depositedBalance[0] = _getDepositedBalance(_accounts[0]);
        depositedBalance[1] = _getDepositedBalance(_accounts[1]);
        
        //just in case, dont claim rewards directly if shutdown
        //can still technically claim via unguarded calls but skipping here
        //protects against outside calls reverting
        if(!isShutdown){
            IConvexRewardPool(convexPool).getReward(address(this));
        }
        _claimExtras();

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
           _calcRewardIntegral(i,_accounts,depositedBalance,supply,false);
        }
        emit UserCheckpoint(_accounts[0],_accounts[1]);
    }

    function _checkpointAndClaim(address[2] memory _accounts) internal nonReentrant{
        uint256 supply = _getTotalSupply();
        uint256[2] memory depositedBalance;
        depositedBalance[0] = _getDepositedBalance(_accounts[0]); //only do first slot
        
        //just in case, dont claim rewards directly if shutdown
        //can still technically claim via unguarded calls but skipping here
        //protects against outside calls reverting
        if(!isShutdown){
            IConvexRewardPool(convexPool).getReward(address(this));
        }
        _claimExtras();

        uint256 rewardCount = rewards.length;
        for (uint256 i = 0; i < rewardCount; i++) {
           _calcRewardIntegral(i,_accounts,depositedBalance,supply,true);
        }
        emit UserCheckpoint(_accounts[0],_accounts[1]);
    }

    //claim any rewards not part of the convex pool
    function _claimExtras() internal virtual{
        //override and add any external reward claiming
        if(rewardHook != address(0)){
            try IRewardHook(rewardHook).onRewardClaim(){
            }catch{}
        }
    }

    function user_checkpoint(address _account) external returns(bool) {
        _checkpoint([_account, address(0)]);
        return true;
    }

    function totalBalanceOf(address _account) external view returns(uint256){
        return _getDepositedBalance(_account);
    }

    //run earned as a mutable function to claim everything before calculating earned rewards
    function earned(address _account) external returns(EarnedData[] memory claimable) {
        //because this is a state mutative function
        //we can simplify the earned() logic of all rewards (internal and external)
        //and allow this contract to be agnostic to outside reward contract design
        //by just claiming everything and updating state via _checkpoint()
         _checkpoint([_account, address(0)]);
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            //skip invalidated rewards
            if(reward.reward_token == address(0)){
                continue;
            }
    
            claimable[i].amount = claimable_reward[reward.reward_token][_account];
            claimable[i].token = reward.reward_token;
        }
        return claimable;
    }

    //set any claimed rewards to automatically go to a different address
    //set address to zero to disable
    function setRewardRedirect(address _to) external nonReentrant{
        rewardRedirect[msg.sender] = _to;
        emit RewardRedirected(msg.sender, _to);
    }

    function getReward(address _account) external {
        //check if there is a redirect address
        if(rewardRedirect[_account] != address(0)){
            _checkpoint([_account, rewardRedirect[_account]]);
        }else{
            //claim directly in checkpoint logic to save a bit of gas
            _checkpoint([_account, _account]);
        }
    }

    function getReward(address _account, address _forwardTo) external {
        require(msg.sender == _account, "!self");
        //claim directly in checkpoint logic to save a bit of gas
        //pack forwardTo into account array to save gas so that a proxy etc doesnt have to double transfer
        _checkpointAndClaim([_account,_forwardTo]);
    }

    //deposit a curve token
    function deposit(uint256 _amount, address _to) public returns (uint256){
        require(!isShutdown, "shutdown");

        //dont need to call checkpoint since _mint() will

        if (_amount > 0) {
            _mint(_to, _amount);
            IERC20(curveToken).safeTransferFrom(msg.sender, address(this), _amount);
            IBooster(convexBooster).deposit(convexPoolId, _amount);
        }

        emit Deposited(msg.sender, _to, _amount, true);
        return _amount;
    }

    //withdraw to curve lp token
    function withdraw(uint256 _amount) public returns (uint256){

        //dont need to call checkpoint since _burn() will
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            if(isShutdown){
                //if the wrapper is shutdown, use emergency withdraw as a precaution since this wrapper doesnt know the reason.
                //assuming claiming still works, it is still possible to claim some rewards
                //by calling the unguarded claim on the base pool and moving rewards to the
                //wrapper before withdrawing/claiming
                IConvexRewardPool(convexPool).emergencyWithdraw(_amount);
            }else{
                IConvexRewardPool(convexPool).withdraw(_amount, false);
            }
            IERC20(curveToken).safeTransfer(msg.sender, _amount);
        }

        emit Withdrawn(msg.sender, _amount, false);
        return _amount;
    }

    function _beforeTokenTransfer(address _from, address _to, uint256) internal override {
        _checkpoint([_from, _to]);
    }
    
    

    ///  IERC 4626 ///
    //add in erc4626 style deposit/withdraws too just to make integrations easier
    //the wrapper does not use shares

    function mint(uint256 _shares, address _to) external override returns (uint256){
        return deposit(_shares,_to);
    }

    function withdraw(uint256 _amount, address _receiver, address ) public override returns(uint256 shares){
        //dont need to call checkpoint since _burn() will
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            if(isShutdown){
                //if the wrapper is shutdown, use emergency withdraw as a precaution since this wrapper doesnt know the reason.
                //assuming claiming still works, it is still possible to claim some rewards
                //by calling the unguarded claim on the base pool and moving rewards to the
                //wrapper before withdrawing/claiming
                IConvexRewardPool(convexPool).emergencyWithdraw(_amount);
            }else{
                IConvexRewardPool(convexPool).withdraw(_amount, false);
            }
            IERC20(curveToken).safeTransfer(_receiver, _amount);
        }

        emit Withdrawn(msg.sender, _amount, false);
        return _amount;
    }

    function redeem(uint256 _shares, address _receiver, address _owner) public override returns (uint256 assets){
        return withdraw(_shares, _receiver, _owner);
    }

    function asset() external override view returns (address){
        return curveToken;
    }

    function totalAssets() public override view returns (uint256){
        return IConvexRewardPool(convexPool).balanceOf(address(this));
    }

    function convertToShares(uint256 _assets) public override pure returns (uint256){
        return _assets;
    }

    function convertToAssets(uint256 _shares) public override pure returns (uint256){
        return _shares;
    }

    function convertToSharesRoundUp(uint256 _assets) internal pure returns (uint256){
        return convertToShares(_assets);
    }

    function convertToAssetsRoundUp(uint256 _shares) internal pure returns (uint256){
        return convertToAssets(_shares);
    }

    function maxDeposit(address) external override view returns (uint256){
        if(isShutdown) return 0;

        return type(uint256).max;
    }
    function maxMint(address) external override view returns (uint256){
        if(isShutdown) return 0;

        return type(uint256).max;
    }
    function previewDeposit(uint256 _amount) public override pure returns (uint256){
        return convertToShares(_amount);
    }
    function previewMint(uint256 _shares) public override pure returns (uint256){
        return convertToAssetsRoundUp(_shares); //round up
    }
    function maxWithdraw(address _owner) external override view returns (uint256){
        return convertToAssets(balanceOf(_owner));
    }
    function previewWithdraw(uint256 _amount) public override pure returns (uint256){
        return convertToSharesRoundUp(_amount); //round up
    }
    function maxRedeem(address _owner) external override view returns (uint256){
        return balanceOf(_owner);
    }
    function previewRedeem(uint256 _shares) public override pure returns (uint256){
        return convertToAssets(_shares);
    }
}