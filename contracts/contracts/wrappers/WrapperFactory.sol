// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IProxyFactory.sol";
import "../interfaces/IStakingWrapper.sol";


//Factory to create wrapped staking positions
contract WrapperFactory{
   
    address public immutable proxyFactory;
    
    address public owner;
    address public pendingOwner;
    bool public isInit;
    uint256 public factoryId;

    address public wrapperImplementation;
    address[] public wrapperList;

    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);
    event ImplementationChanged(address _implementation);
    event WrapperCreated(address _wrapper, uint256 _pid);

    constructor(address _proxyFactory){
        proxyFactory = _proxyFactory;
    }

    function initialize(address _owner, address _implementation, uint256 _factoryId) virtual external {
        require(!isInit,"already init");

        owner = _owner;
        emit OwnerChanged(owner);

        wrapperImplementation = _implementation;

        factoryId = _factoryId;
        isInit = true;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    function count() external view returns(uint256){
        return wrapperList.length;
    }

    //set next owner
    function setPendingOwner(address _po) external onlyOwner{
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

    function setImplementation(address _imp) external onlyOwner{
        wrapperImplementation = _imp;
        emit ImplementationChanged(_imp);
    }

    function CreateWrapper(uint256 _pid) external onlyOwner returns (address) {
        //create
        address wrapper = IProxyFactory(proxyFactory).clone(wrapperImplementation);
        wrapperList.push(wrapper);
        emit WrapperCreated(wrapper, _pid);

        //init
        IStakingWrapper(wrapper).initialize(_pid);
        
        return wrapper;
    }
}