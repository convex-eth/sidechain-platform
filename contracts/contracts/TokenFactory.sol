// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IDeposit.sol";
import "./interfaces/IDepositToken.sol";
import "./interfaces/IProxyFactory.sol";

//factory to create deposit tokens
contract TokenFactory {

    address public immutable operator;
    address public immutable proxyFactory;

    address public implementation;

    constructor(address _operator, address _proxyFactory){
        operator = _operator;
        proxyFactory = _proxyFactory;
    }

    function setImplementation(address _imp) external{
        require(msg.sender == IDeposit(operator).owner(),"!auth");

        implementation = _imp;
    }

    //create a deposit token for a given lptoken
    function CreateDepositToken(address _lptoken) external returns(address){
        require(msg.sender == operator, "!authorized");

        address dtoken = IProxyFactory(proxyFactory).clone(implementation);
        IDepositToken(dtoken).initialize(_lptoken);

        return dtoken;
    }
}
