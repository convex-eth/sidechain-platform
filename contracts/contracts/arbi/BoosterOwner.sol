// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IOwner {
    //booster
    // function setFactories(address _rfactory, address _sfactory, address _tfactory) external;
    function setRescueManager(address _arb) external;
    function setRewardManager(address _arb) external;
    function setRewardFactory(address _arb) external;
    function setFeeDeposit(address _arb) external;
    function setFees(uint256 _fees) external;
    function shutdownSystem() external;
    function shutdownPool(uint256 _pid) external;
    function setPendingOwner(address _po) external;
    function acceptPendingOwner() external;
    function setPoolManager(address _poolM) external;

    function isShutdown() external view returns(bool);
    function poolLength() external view returns(uint256);
    function poolInfo(uint256) external view returns(address,address,address,address,address,bool);
    
    function owner() external view returns(address);
    function rewardFactory() external view returns(address);

    // reward factory
    function setImplementation(address _imp) external;

    //voter owner
    function retireBooster() external;
    function operator() external view returns(address);
}

/*
Immutable booster owner that requires all pools to be shutdown before shutting down the entire convex system
A timelock is required if forcing a shutdown if there is a bugged pool that can not be withdrawn from

Allow arbitrary calls to other contracts, but limit how calls are made to Booster

*/
contract BoosterOwner is ReentrancyGuard{

    address public constant booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant voterproxy = address(0x989AEb4d175e16225E39E87d0D97A3360524AD80);
    address public immutable voterproxyOwner;

    address public owner;
    address public pendingowner;
    bool public isSealed;

    event ShutdownStarted(uint256 executableTimestamp);
    event ShutdownExecuted();
    event TransferOwnership(address pendingOwner);
    event AcceptedOwnership(address newOwner);
    event OwnershipSealed();

    constructor(address _voterProxyOwner) {
        //default to owner of booster
        owner = IOwner(booster).owner();
        voterproxyOwner = _voterProxyOwner;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    function transferOwnership(address _owner) external onlyOwner{
        pendingowner = _owner;
        emit TransferOwnership(_owner);
    }

    function acceptOwnership() external {
        require(pendingowner == msg.sender, "!pendingowner");
        owner = pendingowner;
        pendingowner = address(0);
        emit AcceptedOwnership(owner);
    }

    function sealOwnership() external onlyOwner{
        isSealed = true;
        emit OwnershipSealed();
    }

    function setBoosterOwner() external onlyOwner{
        //allow reverting ownership until sealed
        require(!isSealed, "ownership sealed");

        //transfer booster ownership to this owner
        IOwner(booster).setPendingOwner(owner);
    }

    function acceptPendingOwner() external onlyOwner{
        IOwner(booster).acceptPendingOwner();
    }

    function setRescueManager(address _rescue) external onlyOwner nonReentrant{
        IOwner(booster).setRescueManager(_rescue);
    }

    function setRewardManager(address _rMng) external onlyOwner nonReentrant{
        IOwner(booster).setRewardManager(_rMng);
    }

    function setRewardFactory(address _rfac) external onlyOwner{
        //sealed
        // IOwner(booster).setRewardFactory(_rfac);
    }

    function setFeeDeposit(address _fdep) external onlyOwner nonReentrant{
        IOwner(booster).setFeeDeposit(_fdep);
    }

    function setFees(uint256 _fees) external onlyOwner nonReentrant{
        IOwner(booster).setFees(_fees);
    }

    function setPoolManager(address _poolM) external onlyOwner nonReentrant{
        IOwner(booster).setPoolManager(_poolM);
    }

    function shutdownPool(uint256 _pid) external onlyOwner nonReentrant{
        IOwner(booster).shutdownPool(_pid);
    }

    function shutdownSystem() external onlyOwner nonReentrant{
        uint256 poolCount = IOwner(booster).poolLength();

        //shutdown system
        IOwner(booster).shutdownSystem();
        emit ShutdownExecuted();

        //no pools were added during shutdown?
        require(poolCount == IOwner(booster).poolLength(), "pool cnt");

        //make sure operator did not change during shutdown
        require(IOwner(voterproxyOwner).operator() == booster, "booster changed");
        //replace current voter operator
        IOwner(voterproxyOwner).retireBooster();
    }

    //allow arbitrary calls to any contract other than the booster, as some contracts
    //may use ownership as booster.owner() instead of local variable
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner nonReentrant returns (bool, bytes memory) {
        require(_to != booster, "!invalid target");

        (bool success, bytes memory result) = _to.call{value:_value}(_data);

        return (success, result);
    }


    // --- Helper functions for other systems, could also just use execute() ---

    //reward factory - set implementation
    function setRewardImplementation(address _imp) external onlyOwner nonReentrant{
        IOwner(IOwner(booster).rewardFactory()).setImplementation(_imp);
    }
}