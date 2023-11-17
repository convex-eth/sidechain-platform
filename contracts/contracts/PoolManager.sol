// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IBooster.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IRewardManager.sol";

/*
Pool Manager
*/
contract PoolManager{

    address public owner;
    address public pendingOwner;
    address public operator;
    address public immutable booster;
    address public immutable cvxRewards;

    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);
    event PoolAdded(address indexed _gauge, address _pool);

    constructor(address _booster, address _cvxRewards){
        owner = msg.sender;
        operator = msg.sender;
        booster = _booster;
        cvxRewards = _cvxRewards;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "!op");
        _;
    }

    //set pending owner
    function setPendingOwner(address _po) external onlyOwner{
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

    //set operator - only OWNER
    function setOperator(address _operator) external onlyOwner{
        operator = _operator;
    }

    //revert role of PoolManager back to operator
    function revertControl() external onlyOwner{
        //revert
        IBooster(booster).setPoolManager(owner);
    }

    //add a new curve pool to the system.
    //gauge must be on gauge controller
    function addPool(address _gauge, address _factory) external onlyOperator returns(bool){

        //get lp token
        address lptoken = IGauge(_gauge).lp_token();
        require(lptoken != address(0),"no token");
        
        //add to pool
        uint256 pid = IBooster(booster).poolLength();
        IBooster(booster).addPool(lptoken,_gauge,_factory);

        //get pool address
        (,,address pool,,) = IBooster(booster).poolInfo(pid);

        //add cvx rewards by default
        address rewardmanager = IBooster(booster).rewardManager();
        IRewardManager(rewardmanager).setPoolRewardToken( pool,  IRewardManager(rewardmanager).cvx() );
        IRewardManager(rewardmanager).setPoolRewardContract( pool, IRewardManager(rewardmanager).rewardHook(), cvxRewards );

        emit PoolAdded(_gauge, pool);
        return true;
    }

    //shutdown a pool
    function shutdownPool(uint256 _pid) external onlyOperator returns(bool){
        //shutdown
        IBooster(booster).shutdownPool(_pid);
        return true;
    }

}