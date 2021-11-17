// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IDeposit.sol";
import "./interfaces/IProxyFactory.sol";
import "./interfaces/IVirtualBalanceRewardPool.sol";
import "./interfaces/IBaseRewards.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract RewardFactory {
    using Address for address;

    address public immutable crv;
    address public immutable proxyFactory;

    address public operator;
    address public mainImplementation;
    address public virtualImplementation;
    mapping (address => bool) private rewardAccess;

    constructor(address _operator, address _crv, address _proxyFactory) {
        operator = _operator;
        crv = _crv;
        proxyFactory = _proxyFactory;
    }

    function setImplementation(address _imp, address _virtualImp) external{
        require(msg.sender == IDeposit(operator).owner(),"!auth");

        mainImplementation = _imp;
        virtualImplementation = _virtualImp;
    }

    //stash contracts need access to create new Virtual balance pools for extra gauge incentives(ex. snx)
    function setAccess(address _stash, bool _status) external{
        require(msg.sender == operator, "!auth");
        rewardAccess[_stash] = _status;
    }

    //Create a Managed Reward Pool to handle distribution of all main tokens mined in a pool
    function CreateMainRewards(uint256 _pid, address _depositToken) external returns (address) {
        require(msg.sender == operator, "!auth");

        //operator = booster(deposit) contract so that new crv can be added and distributed
        //reward manager = this factory so that extra incentive tokens(ex. snx) can be linked to the main managed reward pool
        address rewardPool = IProxyFactory(proxyFactory).clone(mainImplementation);
        IBaseRewards(rewardPool).initialize(_pid,_depositToken,crv,operator, address(this));
        return rewardPool;
    }

    //create a virtual balance reward pool that mimicks the balance of a pool's main reward contract
    //used for extra incentive tokens(ex. snx) as well as vecrv fees
    function CreateTokenRewards(address _token, address _mainRewards, address _operator) external returns (address) {
        require(msg.sender == operator || rewardAccess[msg.sender] == true, "!auth");


        address rewardPool = IProxyFactory(proxyFactory).clone(mainImplementation);

        //create new pool, use main pool for balance lookup
        IVirtualBalanceRewardPool(rewardPool).initialize(_mainRewards,_token,_operator);

        //add the new pool to main pool's list of extra rewards, assuming this factory has "reward manager" role
        IBaseRewards(_mainRewards).addExtraReward(rewardPool);

        //return new pool's address
        return rewardPool;
    }
}
