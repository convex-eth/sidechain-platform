// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IPools.sol";
import "./interfaces/IGauge.sol";

/*
Pool Manager
*/
contract PoolManager{

    // address public constant gaugeController = address(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

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
    function addPool(address _gauge, uint256 _stashVersion) external returns(bool){
        //use admin controls until we find a way to get gauged pools
        require(msg.sender == operator, "!auth");
        require(_gauge != address(0),"gauge is 0");

        //TODO: how to get list of gauges with weight?
        // uint256 weight = IGaugeController(gaugeController).get_gauge_weight(_gauge);
        // require(weight > 0, "must have weight");

        bool gaugeExists = IPools(pools).gaugeMap(_gauge);
        require(!gaugeExists, "already registered");

        address lptoken = IGauge(_gauge).lp_token();
        require(lptoken != address(0),"no token");
        
        IPools(pools).addPool(lptoken,_gauge,_stashVersion);

        return true;
    }

    function shutdownPool(uint256 _pid) external returns(bool){
        require(msg.sender==operator, "!auth");

        IPools(pools).shutdownPool(_pid);
        return true;
    }

}