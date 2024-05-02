// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IBooster.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IRewardHook.sol";


/*
    A Hook contract that pools call to perform extra actions when updating rewards
    (Example: claiming extra rewards from an outside contract)
*/
contract PoolRewardHook is IRewardHook{

    address public immutable booster;
    mapping(address => address[]) public poolRewardList;

    event PoolRewardAdded(address indexed pool, address rewardContract);
    event PoolRewardReset(address indexed pool);

    constructor(address _booster) {
        booster = _booster;
    }

    //get reward manager role from booster to use as admin
    function rewardManager() public view returns(address){
        return IBooster(booster).rewardManager();
    }

    //get reward contract list count for given pool/account
    function poolRewardLength(address _pool) external view returns(uint256){
        return poolRewardList[_pool].length;
    }

    //clear reward contract list for given pool/account
    function clearPoolRewardList(address _pool) external{
        require(msg.sender == rewardManager(), "!rmanager");

        delete poolRewardList[_pool];
        emit PoolRewardReset(_pool);
    }

    //add a reward contract to the list of contracts for a given pool/account
    function addPoolReward(address _pool, address _rewardContract) external{
        require(msg.sender == rewardManager(), "!rmanager");

        poolRewardList[_pool].push(_rewardContract);
        emit PoolRewardAdded(_pool, _rewardContract);
    }

    //call all reward contracts to claim. (unguarded)
    function onRewardClaim() external{
        uint256 rewardLength = poolRewardList[msg.sender].length;
        for(uint256 i = 0; i < rewardLength; i++){
            //use try-catch as this could be a 3rd party contract
            //use try-catch as this could be a 3rd party contract
            (bool success, bytes memory data) = address(
                poolRewardList[msg.sender][i]
            ).call(
                    abi.encodeWithSelector(
                        IRewards(poolRewardList[msg.sender][i])
                            .getReward
                            .selector,
                        msg.sender
                    )
                );
            if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
                return;
            }
        }
    }

}