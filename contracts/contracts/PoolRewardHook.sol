// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IDeposit.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IRewardHook.sol";


/*
    Hook pools call to perform extra actions when updating rewards
*/
contract PoolRewardHook is IRewardHook{

    address public immutable booster;
    mapping(address => address[]) public poolRewardList;

    event PoolRewardAdded(address indexed pool, address rewardContract);
    event PoolRewardReset(address indexed pool);

    constructor(address _booster) {
        booster = _booster;
    }

    function rewardManager() public view returns(address){
        return IDeposit(booster).rewardManager();
    }

    function poolRewardLength(address _pool) external view returns(uint256){
        return poolRewardList[_pool].length;
    }

    function clearPoolRewardList(address _pool) external{
        require(msg.sender == rewardManager(), "!rmanager");

        delete poolRewardList[_pool];
        emit PoolRewardReset(_pool);
    }

    function addPoolReward(address _pool, address _rewardContract) external{
        require(msg.sender == rewardManager(), "!rmanager");

        poolRewardList[_pool].push(_rewardContract);
        emit PoolRewardAdded(_pool, _rewardContract);
    }

    function onRewardClaim() external{
        uint256 rewardLength = poolRewardList[msg.sender].length;
        for(uint256 i = 0; i < rewardLength; i++){
            IRewards(poolRewardList[msg.sender][i]).getReward(msg.sender);
        }
    }

}