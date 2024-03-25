// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IRewards.sol";
import "./interfaces/IRewardFactory.sol";
import "./interfaces/IStaker.sol";
import "./interfaces/IFeeDistro.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IRewardManager.sol";
import "./interfaces/ITokenMinter.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
This is the main contract which will have operator role on the VoterProxy.
Handles pool creation, deposits/withdraws, as well as other managment functions like factories/managers/fees
*/
contract Booster is ReentrancyGuard{
    using SafeERC20 for IERC20;

    uint256 public fees = 1700; //platform fees
    uint256 public constant MaxFees = 2500; //hard code max fees
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public owner; //owner
    address public pendingOwner; //pending owner
    address public poolManager; //add and shutdown pools
    address public mintManager; //mint tokens that voteproxy has ownership of
    address public rescueManager; //specific role just for pulling non-lp/gauge tokens from voterproxy
    address public rewardManager; //controls rewards
    address public immutable staker; //voter proxy
    address public rewardFactory; //factory for creating main reward/staking pools
    address public feeDeposit; //address where fees are accumulated

    bool public isShutdown; //flag if booster is shutdown or not

    struct PoolInfo {
        address lptoken; //the curve lp token
        address gauge; //the curve gauge
        address rewards; //the main reward/staking contract
        bool shutdown; //is this pool shutdown?
        address factory; //a reference to the curve factory used to create this pool (needed for minting crv)
    }


    PoolInfo[] public poolInfo;//list of convex pools, index(pid) -> pool
    mapping(address => address) public factoryCrv;//map defining CRV token used by a Curve factory
    mapping(address => bool) public activeMap;//map defining if a curve gauge/lp token is already being used or not
    mapping(uint256 => uint256) public shutdownBalances; //lp balances of a shutdown pool, index(pid) -> lp balance

    event Deposited(address indexed user, uint256 indexed poolid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolid, uint256 amount);
    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);
    event CrvFactorySet(address indexed _factory, address _crv);
    event FeesChanged(uint256 _fees);
    event FeeDepositChanged(address _feedeposit);

    constructor(address _staker) {
        isShutdown = false;
        staker = _staker;
        owner = msg.sender;
        poolManager = msg.sender;
        mintManager = msg.sender;
        rescueManager = msg.sender;
    }

    function _proxyCall(address _to, bytes memory _data) internal{
        (bool success,) = IStaker(staker).execute(_to,uint256(0),_data);
        require(success, "Proxy Call Fail");
    }

    /// SETTER SECTION ///

    //set next pending owner. owner must accept
    function setPendingOwner(address _po) external {
        require(msg.sender == owner, "!auth");
        pendingOwner = _po;
        emit SetPendingOwner(_po);
    }

    //claim ownership
    function acceptPendingOwner() external {
        require(msg.sender == pendingOwner, "!p_owner");

        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerChanged(owner);
    }

    //set CRV token address used by a specific Curve pool factory.
    //While CRV could be set as immutable, there is no guarantee that a side chain token won't be changed.
    //(for example a new/different bridge platform is used)
    function setFactoryCrv(address _factory, address _crv) external {
        require(msg.sender == owner, "!auth");
        require(_factory != address(0) && _crv != address(0), "invalid");
        factoryCrv[_factory] = _crv;

        emit CrvFactorySet(_factory, _crv);
    }

    //set a pool manager
    //note: only the pool manager can relinquish control
    function setPoolManager(address _poolM) external {
        require(msg.sender == poolManager, "!auth");
        require(_poolM != address(0),"invalid address");
        poolManager = _poolM;
    }

    //set a mint manager
    //note: only the mint manager can relinquish control
    function setMintManager(address _mintM) external {
        require(msg.sender == mintManager, "!auth");
        require(_mintM != address(0),"invalid address");
        mintManager = _mintM;
    }

    //set a rescue manager for tokens
    //set by owner. separate role though in case something needs to be streamlined like claiming outside rewards.
    function setRescueManager(address _rescueM) external {
        require(msg.sender == owner, "!auth");
        rescueManager = _rescueM;
    }

    //set reward manager
    //can add extra rewards and reward hooks on pools
    function setRewardManager(address _rewardM) external {
        require(msg.sender == owner, "!auth");
        require(IRewardManager(_rewardM).rewardHook() != address(0), "!no hook");
        require(IRewardManager(_rewardM).cvx() != address(0), "!no cvx");

        rewardManager = _rewardM;
    }

    //set factories used when deploying new reward/token contracts
    function setRewardFactory(address _rfactory) external {
        require(msg.sender == owner, "!auth");
        require(rewardFactory == address(0), "sealed");
        
        rewardFactory = _rfactory;
    }

    //set address that receives platform fees
    function setFeeDeposit(address _deposit) external {
        require(msg.sender == owner, "!auth");
        
        feeDeposit = _deposit;
        emit FeeDepositChanged(_deposit);
    }

    //set platform fees
    function setFees(uint256 _platformFees) external{
        require(msg.sender == owner, "!auth");
        require(_platformFees <= MaxFees, ">MaxFees");

        fees = _platformFees;
        emit FeesChanged(_platformFees);
    }

    //rescue a token from the voter proxy
    //token must not be an lp or gauge token
    function rescueToken(address _token, address _to) external{
        require(msg.sender==rescueManager, "!auth");

        IStaker(staker).rescue(_token, _to);
    }

    function setTokenMinterOperator(address _token, address _minter, bool _active) external{
        require(msg.sender==mintManager, "!auth");

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setOperator(address,bool)")), _minter, _active);
        _proxyCall(_token, data);
    }

    /// END SETTER SECTION ///

    //get pool count
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //create a new pool
    function addPool(address _lptoken, address _gauge, address _factory) external nonReentrant returns(bool){
        //only manager
        require(msg.sender==poolManager && !isShutdown, "!add");
        //basic checks
        require(_gauge != address(0) && _lptoken != address(0) && _factory != address(0),"!param");
        //crv check
        require(factoryCrv[_factory] != address(0), "!crv");
        //an unused pool
        require(!activeMap[_gauge] && !activeMap[_lptoken],"already reg");

        //check that the given factory is indeed tied with the gauge
        require(IPoolFactory(_factory).is_valid_gauge(_gauge),"!factory gauge");

        //the next pool's pid
        uint256 pid = poolInfo.length;

        //create a reward contract for rewards
        address newRewardPool = IRewardFactory(rewardFactory).CreateMainRewards(factoryCrv[_factory],_gauge,_lptoken,pid);

        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                gauge: _gauge,
                rewards: newRewardPool,
                shutdown: false,
                factory: _factory
            })
        );
        
        //set gauge as being used
        activeMap[_gauge] = true;
        //also set the lp token as used
        activeMap[_lptoken] = true;

        //set gauge redirect
        setGaugeRedirect(_gauge, newRewardPool);

        return true;
    }

    //shutdown pool, only call from pool manager
    function shutdownPool(uint256 _pid) external nonReentrant returns(bool){
        require(msg.sender==poolManager, "!auth");
        return _shutdownPool(_pid);
    }

    //shutdown pool internal call
    function _shutdownPool(uint256 _pid) internal returns(bool){
        
        PoolInfo storage pool = poolInfo[_pid];
        if(pool.shutdown){
            //already shut down
            return false;
        }  

        uint256 lpbalance = IERC20(pool.lptoken).balanceOf(address(this));

        //withdraw from gauge
        try IStaker(staker).withdrawAll(pool.lptoken,pool.gauge){
        }catch{}

        //lp difference
        lpbalance = IERC20(pool.lptoken).balanceOf(address(this)) - lpbalance;

        //record how many lp tokens were returned
        //this is important to prevent a fake gauge attack which inflates deposit tokens
        //in order to withdraw another pool's legitamate lp tokens
        shutdownBalances[_pid] = lpbalance;

        //flag pool as shutdown
        pool.shutdown = true;
        //reset active map
        activeMap[pool.gauge] = false;
        activeMap[pool.lptoken] = false;
        return true;
    }

    //shutdown this contract.
    //  unstake and pull all lp tokens to this address
    //  only allow withdrawals
    function shutdownSystem() external nonReentrant{
        require(msg.sender == owner, "!auth");
        
        //remove pool manager while shutting down so that no new pools can be added during the loop
        address currentPoolManager = poolManager;
        poolManager = address(0);

        //shutdown all pools.
        //gas cost could grow too large to do all, in which case individual pools should be shutdown first
        for(uint i=0; i < poolInfo.length; i++){
            _shutdownPool(i);
        }

        //flag system as shutdown at the end
        isShutdown = true;

        //revert pool manager
        poolManager = currentPoolManager;
    }


    //deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant returns(bool){
        require(!isShutdown,"shutdown");
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        //send to proxy to stake
        address lptoken = pool.lptoken;
        IERC20(lptoken).safeTransferFrom(msg.sender, staker, _amount);

        //stake
        address gauge = pool.gauge;
        require(gauge != address(0),"!gauge setting");
        IStaker(staker).deposit(lptoken,gauge,_amount);

        //mint reward tokens for user
        IRewards(pool.rewards).stakeFor(msg.sender,_amount);
        
        
        emit Deposited(msg.sender, _pid, _amount);
        return true;
    }

    //deposit all lp tokens and stake
    function depositAll(uint256 _pid) external returns(bool){
        address lptoken = poolInfo[_pid].lptoken;
        uint256 balance = IERC20(lptoken).balanceOf(msg.sender);
        deposit(_pid,balance);
        return true;
    }

    //withdraw lp tokens
    function _withdraw(uint256 _pid, uint256 _amount, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        address lptoken = pool.lptoken;
        address gauge = pool.gauge;


        //pull from gauge if not shutdown
        if (!pool.shutdown) {
            //get prev balance to double check difference
            uint256 lpbalance = IERC20(lptoken).balanceOf(address(this));

            //because of activeMap, a gauge and its lp token can only be assigned to a single unique pool
            //thus claims for withdraw here are enforced to be the correct pair
            IStaker(staker).withdraw(lptoken, gauge, _amount);

            //also check that the amount returned was correct
            //which will safegaurd pools that have been shutdown
            require(IERC20(lptoken).balanceOf(address(this)) - lpbalance >= _amount, "withdraw amount fail");
        }else{
            //if shutdown, tokens will be held in this contract
            //remove from shutdown balances. revert if not enough
            //would only revert if something was wrong with the pool
            //and shutdown didnt return lp tokens
            //thus this is a catch to stop other pools with same lp token from
            //being affected
            shutdownBalances[_pid] -= _amount;
        }

        //return lp tokens
        IERC20(lptoken).safeTransfer(_to, _amount);

        emit Withdrawn(_to, _pid, _amount);
    }

    //allow reward contracts to withdraw directly to user
    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external nonReentrant returns(bool){
        //require sender to be the reward contract for a given pool
        address rewardContract = poolInfo[_pid].rewards;
        require(msg.sender == rewardContract,"!auth");

        //trust is on the reward contract to properly bookkeep deposit token balance
        //since the reward contract is now the deposit token itself
        _withdraw(_pid,_amount,_to);
        return true;
    }

    //claim crv for a pool from the pool's factory and send to rewards
    function claimCrv(uint256 _pid, address _gauge) external {
        //can only be called by the pool's reward contract
        address rewardContract = poolInfo[_pid].rewards;
        require(msg.sender == rewardContract,"!auth");

        //only claim if the pool isnt shutdown, but no need to revert
        if(!poolInfo[_pid].shutdown){
            //claim crv and redirect to the reward contract
            address _factory = poolInfo[_pid].factory;
            IStaker(staker).claimCrv(factoryCrv[_factory], _factory, _gauge, rewardContract);
        }
    }

    //set a gauge's redirect setting to claim extra rewards directly to a reward contract 
    //instead of being pulled to the voterproxy/staker contract 
    function setGaugeRedirect(address _gauge, address _rewards) internal returns(bool){
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("set_rewards_receiver(address)")), _rewards);
        _proxyCall(_gauge, data);
        return true;
    }

    //given an amount of crv, calculate fees
    function calculatePlatformFees(uint256 _amount) external view returns(uint256){
        uint256 _fees = _amount * fees / FEE_DENOMINATOR;
        return _fees;
    }
}