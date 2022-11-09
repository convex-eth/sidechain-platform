// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IGauge.sol";
import "./interfaces/IBooster.sol";
import "./interfaces/IConvexRewardPool.sol";
import "./interfaces/IRewardHook.sol";
import "./interfaces/IExtraRewardPool.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';


/*
This is a utility library which is mainly used for off chain calculations
*/
contract PoolUtilities{

    uint256 private constant WEEK = 7 * 86400;

    address public constant convexProxy = address(0x989AEb4d175e16225E39E87d0D97A3360524AD80);
    address public immutable crv;
    address public immutable booster;

    constructor(address _booster, address _crv){
        booster = _booster;
        crv = _crv;
    }


    //get boosted reward rate of user at a specific staking contract
    //returns amount user receives per second based on weight/liq ratio
    //%return = userBoostedRewardRate * timeFrame * price of reward / price of LP / 1e18
    function gaugeRewardRates(uint256 _pid, uint256 _week) public view returns (uint256[] memory boostedRates) {
        //get pool info
        (, address gauge, , ,) = IBooster(booster).poolInfo(_pid);

        uint256 week = _week;

        if(week == 0){
            //get current period -> timestamp from period
            uint256 period = IGauge(gauge).period();
            uint256 periodTime = IGauge(gauge).period_timestamp(period);

            //get week from last checkpointed period
            week = periodTime / WEEK;
        }

        //get inflation rate
        uint256 infRate = IGauge(gauge).inflation_rate(week);

        //if inflation is 0, there might be tokens on the gauge and not checkpointed yet
        if(infRate == 0){
            infRate = IERC20(crv).balanceOf(gauge) / WEEK;
        }

        //if inflation is still 0... might have not bridged yet, or lost gauge weight


        //get working supply
        uint256 wsupply = IGauge(gauge).working_supply();

        if(wsupply > 0){
            infRate = infRate * 1e18 / wsupply;
        }

        //get convex working balance
        uint256 wbalance = IGauge(gauge).working_balances(convexProxy);
        //get convex deposited balance
        uint256 dbalance = IGauge(gauge).balanceOf(convexProxy);

        //convex inflation rate
        uint256 cvxInfRate = infRate;
        //if no balance, just return a full boosted rate
        if(wbalance > 0){
            //wbalance and dbalance will cancel out if full boost
            cvxInfRate = infRate * wbalance / dbalance;
        }

        //number of gauge rewards
        uint256 gaugeRewards = IGauge(gauge).reward_count();

        //make list of reward rates
        boostedRates = new uint256[](gaugeRewards + 1);

        //index 0 will be crv
        boostedRates[0] = cvxInfRate;

        //loop through rewards
        for(uint256 i = 0; i < gaugeRewards; i++){
            (,, uint256 rrate,,) = IGauge(gauge).reward_data(IGauge(gauge).reward_tokens(i));

            //get rate per supply
            if(wsupply > 0){
                rrate = rrate * 1e18 / wsupply;
            }

            //set rate (assume full boosted)
            boostedRates[i+1] = rrate; // * 1e18 / poolSupply;

            //get real boosted rate if balance is positive
            if(wbalance > 0){
                //if full boost, wbalance and dbalance will cancel out
                boostedRates[i+1] = rrate * wbalance / dbalance;// * 1e18 / poolSupply;
            }
        }
    }

     function externalRewardContracts(uint256 _pid) public view returns (address[] memory rewardContracts) {
        //get pool info
        (, , address rewards, ,) = IBooster(booster).poolInfo(_pid);

        //get reward hook
        address hook = IConvexRewardPool(rewards).rewardHook();

        uint256 rewardCount = IRewardHook(hook).poolRewardLength(rewards);
        rewardContracts = new address[](rewardCount);

        for(uint256 i = 0; i < rewardCount; i++){
            rewardContracts[i] = IRewardHook(hook).poolRewardList(rewards, i);
        }
    }

    function aggregateExtraRewardRates(uint256 _pid) external view returns(address[] memory tokens, uint256[] memory rates){
        address[] memory rewardContracts = externalRewardContracts(_pid);

        //limit to 10 for easier logic
        tokens = new address[](10);
        rates = new uint256[](10);

        for(uint256 i = 0; i < rewardContracts.length; i++){
            IExtraRewardPool.PoolType pt = IExtraRewardPool(rewardContracts[i]).poolType();
            if(pt == IExtraRewardPool.PoolType.Single){
                (address t, uint256 r) = singleRewardRate(_pid, rewardContracts[i]);
                tokens[i] = t;
                rates[i] = r;
            }
        }
    }

    function singleRewardRate(uint256 _pid, address _rewardContract) public view returns (address token, uint256 rate) {
        //get pool info
        (, , address rewards, ,) = IBooster(booster).poolInfo(_pid);

        uint256 globalRate = IExtraRewardPool(_rewardContract).rewardRate();
        uint256 totalSupply = IExtraRewardPool(_rewardContract).totalSupply();
        token = IExtraRewardPool(_rewardContract).rewardToken();

        if(totalSupply > 0){
            //get rate for whole pool (vs other pools)
            uint256 poolRate = globalRate * IExtraRewardPool(_rewardContract).balanceOf(rewards) / totalSupply;

            //get pool total supply
            uint256 poolSupply = IConvexRewardPool(rewards).totalSupply();

            //rate per deposit
            rate = poolRate * 1e18 / poolSupply;
        }
    }
}
