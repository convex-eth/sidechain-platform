// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IPools.sol";
import "./interfaces/IGauge.sol";

/*
Pool Manager
*/
contract PoolManager{

    address public operator;
    address public immutable pools;


    constructor(address _pools){
        operator = msg.sender;
        pools = _pools;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    //revert control of adding  pools back to operator
    function revertControl() external{
        require(msg.sender == operator, "!auth");
        IPools(pools).setPoolManager(operator);
    }

    //add a new curve pool to the system.
    //gauge must be on gauge controller
    function addPool(address _gauge, address _factory) external returns(bool){
        //use admin controls until we find a way to get gauged pools
        require(msg.sender == operator, "!auth");

        //get lp token
        address lptoken = IGauge(_gauge).lp_token();
        require(lptoken != address(0),"no token");
        
        IPools(pools).addPool(lptoken,_gauge,_factory);

        return true;
    }

    function shutdownPool(uint256 _pid) external returns(bool){
        require(msg.sender==operator, "!auth");

        IPools(pools).shutdownPool(_pid);
        return true;
    }

}