// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IBooster.sol";
import "./interfaces/IProxyFactory.sol";
import "./interfaces/IConvexRewardPool.sol";


//factory to create reward pools
contract RewardFactory {

    address public immutable proxyFactory;
    address public immutable staker;
    address public immutable operator;
    
    address public mainImplementation;

    constructor(address _operator, address _staker, address _proxyFactory) {
        operator = _operator;
        staker = _staker;
        proxyFactory = _proxyFactory;
    }

    function setImplementation(address _imp) external{
        require(msg.sender == IBooster(operator).owner(),"!auth");

        mainImplementation = _imp;
    }

    //Create a reward pool for a given pool
    function CreateMainRewards(address _crv, address _gauge, address _depositToken, uint256 _pid) external returns (address) {
        require(msg.sender == operator, "!auth");

        address rewardPool = IProxyFactory(proxyFactory).clone(mainImplementation);
        IConvexRewardPool(rewardPool).initialize(_crv, _gauge, staker, operator,_depositToken, _pid);
        
        return rewardPool;
    }
}
