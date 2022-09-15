// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IRewards.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/IRewardFactory.sol";
import "./interfaces/IStaker.sol";
import "./interfaces/ITokenMinter.sol";
import "./interfaces/IFeeDistro.sol";
import "./interfaces/IPoolFactory.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract Booster{
    using SafeERC20 for IERC20;

    address public immutable crv;

    uint256 public fees = 1700; //platform fees
    uint256 public constant MaxFees = 2500;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public owner;
    address public pendingOwner;
    address public feeManager;
    address public poolManager;
    address public rescueManager;
    address public rewardManager;
    address public immutable staker;
    address public rewardFactory;
    address public tokenFactory;
    address public feeDeposit;

    bool public isShutdown;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address rewards;
        bool shutdown;
        address factory;
    }

    //index(pid) -> pool
    PoolInfo[] public poolInfo;
    mapping(address => bool) public gaugeMap;
    mapping(uint256 => uint256) public shutdownBalances; //pid -> lp balance

    event Deposited(address indexed user, uint256 indexed poolid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolid, uint256 amount);
    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);

    constructor(address _staker, address _crv) {
        isShutdown = false;
        staker = _staker;
        owner = msg.sender;
        feeManager = msg.sender;
        poolManager = msg.sender;
        rescueManager = msg.sender;
        rewardManager = msg.sender;
        crv = _crv;
    }


    /// SETTER SECTION ///

    //set next owner
    function setPendingOwner(address _po) external {
        require(msg.sender == owner, "!auth");
        pendingOwner = _po;
        emit SetPendingOwner(_po);
    }

    //claim ownership
    function acceptPendingOwner() external {
        require(pendingOwner != address(0) && msg.sender == pendingOwner, "!p_owner");

        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerChanged(owner);
    }

    function setFeeManager(address _feeM) external {
        require(msg.sender == feeManager, "!auth");
        feeManager = _feeM;
    }

    function setPoolManager(address _poolM) external {
        require(msg.sender == poolManager, "!auth");
        poolManager = _poolM;
    }

    function setRescueManager(address _rescueM) external {
        require(msg.sender == owner, "!auth");
        rescueManager = _rescueM;
    }

    function setRewardManager(address _rewardM) external {
        require(msg.sender == owner, "!auth");
        rewardManager = _rewardM;
    }

    function setFactories(address _rfactory, address _tfactory) external {
        require(msg.sender == owner, "!auth");
        
        rewardFactory = _rfactory;
        tokenFactory = _tfactory;
    }

    function setFeeDeposit(address _deposit) external {
        require(msg.sender == owner, "!auth");
        
        feeDeposit = _deposit;
    }

    function setFees(uint256 _platformFees) external{
        require(msg.sender==feeManager, "!auth");
        require(_platformFees <= MaxFees, ">MaxFees");

        fees = _platformFees;
    }

    function rescueToken(address _token, address _to) external{
        require(msg.sender==rescueManager, "!auth");

        IStaker(staker).rescue(_token, _to);
    }

    /// END SETTER SECTION ///

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //create a new pool
    function addPool(address _lptoken, address _gauge, address _factory) external returns(bool){
        require(msg.sender==poolManager && !isShutdown, "!add");
        require(_gauge != address(0) && _lptoken != address(0) && _factory != address(0),"!param");
        require(!gaugeMap[_gauge] && !gaugeMap[_lptoken],"gaugeMap");

        //check that the given factory is indeed tied with the gauge
        require(IPoolFactory(_factory).is_valid_gauge(_gauge),"!factory gauge");

        //the next pool's pid
        uint256 pid = poolInfo.length;

        //create a tokenized deposit
        address token = ITokenFactory(tokenFactory).CreateDepositToken(_lptoken);
        //create a reward contract for rewards
        address newRewardPool = IRewardFactory(rewardFactory).CreateMainRewards(_gauge,token,pid);



        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                token: token,
                gauge: _gauge,
                rewards: newRewardPool,
                shutdown: false,
                factory: _factory
            })
        );
        gaugeMap[_gauge] = true;

        //set gauge redirect
        setGaugeRedirect(_gauge, newRewardPool);

        //allow booster to stake to the reward pool
        //safe because deposit token is only ever on this booster contract
        //when deposit is a "depost and stake". there should be no free floating deposit tokens
        IERC20(token).approve(newRewardPool, type(uint256).max);

        return true;
    }

    //shutdown pool
    function shutdownPool(uint256 _pid) external returns(bool){
        require(msg.sender==poolManager, "!auth");
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.shutdown,"already shutdown");

        uint256 lpbalance = IERC20(pool.lptoken).balanceOf(address(this));

        //withdraw from gauge
        try IStaker(staker).withdrawAll(pool.lptoken,pool.gauge){
        }catch{}

        //lp difference
        lpbalance = IERC20(pool.lptoken).balanceOf(address(this)) - lpbalance;
        //record how many lp tokens were returned
        shutdownBalances[_pid] = lpbalance;


        pool.shutdown = true;
        gaugeMap[pool.gauge] = false;
        return true;
    }

    //shutdown this contract.
    //  unstake and pull all lp tokens to this address
    //  only allow withdrawals
    function shutdownSystem() external{
        require(msg.sender == owner, "!auth");
        isShutdown = true;

        for(uint i=0; i < poolInfo.length; i++){
            PoolInfo storage pool = poolInfo[i];
            if (pool.shutdown) continue;

            address token = pool.lptoken;
            address gauge = pool.gauge;

            //withdraw from gauge
            try IStaker(staker).withdrawAll(token,gauge){
                pool.shutdown = true;
            }catch{}
        }
    }


    //deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount, bool _stake) public returns(bool){
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

        address token = pool.token;
        if(_stake){
            //mint here and send to rewards on user behalf
            ITokenMinter(token).mint(address(this),_amount);
            IRewards(pool.rewards).stakeFor(msg.sender,_amount);
        }else{
            //add user balance directly
            ITokenMinter(token).mint(msg.sender,_amount);
        }

        
        emit Deposited(msg.sender, _pid, _amount);
        return true;
    }

    //deposit all lp tokens and stake
    function depositAll(uint256 _pid, bool _stake) external returns(bool){
        address lptoken = poolInfo[_pid].lptoken;
        uint256 balance = IERC20(lptoken).balanceOf(msg.sender);
        deposit(_pid,balance,_stake);
        return true;
    }

    //withdraw lp tokens
    function _withdraw(uint256 _pid, uint256 _amount, address _from, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        address lptoken = pool.lptoken;
        address gauge = pool.gauge;

        //remove lp balance
        address token = pool.token;
        ITokenMinter(token).burn(_from,_amount);

        //pull from gauge if not shutdown
        // if shutdown tokens will be in this contract
        if (!pool.shutdown) {
            uint256 lpbalance = IERC20(lptoken).balanceOf(address(this));
            IStaker(staker).withdraw(lptoken, gauge, _amount);
            require(IERC20(lptoken).balanceOf(address(this)) - lpbalance >= _amount, "withdraw amount fail");
        }else{
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

    //withdraw lp tokens
    function withdraw(uint256 _pid, uint256 _amount) public returns(bool){
        _withdraw(_pid,_amount,msg.sender,msg.sender);
        return true;
    }

    //withdraw all lp tokens
    function withdrawAll(uint256 _pid) public returns(bool){
        address token = poolInfo[_pid].token;
        uint256 userBal = IERC20(token).balanceOf(msg.sender);
        withdraw(_pid, userBal);
        return true;
    }

    //allow reward contracts to send here and withdraw to user
    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns(bool){
        address rewardContract = poolInfo[_pid].rewards;
        require(msg.sender == rewardContract,"!auth");

        _withdraw(_pid,_amount,msg.sender,_to);
        return true;
    }

    function claimCrv(uint256 _pid, address _gauge) external{
        address rewardContract = poolInfo[_pid].rewards;
        require(msg.sender == rewardContract,"!auth");

        //claim crv to rewards
        IStaker(staker).claimCrv(poolInfo[_pid].factory, _gauge, rewardContract);
    }

    function setGaugeRedirect(address _gauge, address _rewards) internal returns(bool){
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("set_rewards_receiver(address)")), _rewards);
        IStaker(staker).execute(_gauge,uint256(0),data);
        return true;
    }

    function calculatePlatformFees(uint256 _amount) external view returns(uint256){
        uint256 _fees = _amount * fees / FEE_DENOMINATOR;
        return _fees;
    }

    //claim platform fees
    function processFees() external {
        //crv balance: any crv on this contract is considered part of fees
        uint256 crvBal = IERC20(crv).balanceOf(address(this));

        if (crvBal > 0) {
            //send to a fee depositor that knows how to process
            IERC20(crv).safeTransfer(feeDeposit, crvBal);
            IFeeDistro(feeDeposit).onFeesClaimed();
        }
    }

}