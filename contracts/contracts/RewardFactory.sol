// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IDeposit.sol";
import "./interfaces/IProxyFactory.sol";
import "./interfaces/IConvexRewardPool.sol";


//factory to create reward pools
contract RewardFactory {

    address public immutable crv;
    address public immutable proxyFactory;
    address public immutable staker;

    address public operator;
    address public mainImplementation;

    constructor(address _operator, address _staker, address _crv, address _proxyFactory) {
        operator = _operator;
        staker = _staker;
        crv = _crv;
        proxyFactory = _proxyFactory;
    }

    function setImplementation(address _imp) external{
        require(msg.sender == IDeposit(operator).owner(),"!auth");

        mainImplementation = _imp;
    }

    //Create a reward pool for a given pool
    function CreateMainRewards(address _gauge, address _depositToken, uint256 _pid) external returns (address) {
        require(msg.sender == operator, "!auth");

        address rewardPool = IProxyFactory(proxyFactory).clone(mainImplementation);
        IConvexRewardPool(rewardPool).initialize(crv, _gauge, staker, operator,_depositToken, _pid);
        
        return rewardPool;
    }
}
