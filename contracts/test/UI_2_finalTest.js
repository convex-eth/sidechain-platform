// const { BN, constants, expectEvent, expectRevert, time } = require('openzeppelin-test-helpers');
const { BN, time } = require('openzeppelin-test-helpers');
var jsonfile = require('jsonfile');
var contractList = jsonfile.readFileSync('./contracts.json');

const VoterProxy = artifacts.require("VoterProxy");
const Booster = artifacts.require("Booster");
const ProxyFactory = artifacts.require("ProxyFactory");
const RewardFactory = artifacts.require("RewardFactory");
const ConvexRewardPool = artifacts.require("ConvexRewardPool");
const FeeDeposit = artifacts.require("FeeDeposit");
const IGauge = artifacts.require("IGauge");
const RewardManager = artifacts.require("RewardManager");
const PoolRewardHook = artifacts.require("PoolRewardHook");
const ExtraRewardPool = artifacts.require("ExtraRewardPool");
const DummyToken = artifacts.require("DummyToken");

const IERC20 = artifacts.require("IERC20");
const ERC20 = artifacts.require("ERC20");


const unlockAccount = async (address) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_unlockUnknownAccount",
        params: [address],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });
};


const getChainContracts = () => {
  let NETWORK = config.network;//process.env.NETWORK;
  console.log("network: " +NETWORK);
  var contracts = {};

  if(NETWORK == "debugArb"){
    contracts = contractList.arbitrum;
  }

  console.log("using crv: " +contracts.curve.crv);
  return contracts;
}

const advanceTime = async (secondsElaspse) => {
  await time.increase(secondsElaspse);
  await time.advanceBlock();
  console.log("\n  >>>>  advance time " +(secondsElaspse/86400) +" days  >>>>\n");
}
const day = 86400;

contract("Deploy System and test staking/rewards", async accounts => {
  it("should deploy contracts and test various functions", async () => {

    let deployer = "0x947B7742C403f20e5FaCcDAc5E092C943E7D0277";
    let multisig = "0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB";
    let addressZero = "0x0000000000000000000000000000000000000000"
    let voteproxy = "0x989AEb4d175e16225E39E87d0D97A3360524AD80";

    let userA = accounts[0];
    let userB = accounts[1];
    let userC = accounts[2];
    let userD = accounts[3];
    let userZ = "0xAAc0aa431c237C2C0B5f041c8e59B3f1a43aC78F";
    var userNames = {};
    userNames[userA] = "A";
    userNames[userB] = "B";
    userNames[userC] = "C";
    userNames[userD] = "D";
    userNames[userZ] = "Z";

    let chainContracts = getChainContracts();
    let crv = await IERC20.at(chainContracts.curve.crv);

    //send deployer eth
    await web3.eth.sendTransaction({from:userA, to:deployer, value:web3.utils.toWei("10.0", "ether") });
    console.log("sent eth to deployer");

    console.log("\n\n >>>> deploy system >>>>")

    var usingproxy = await VoterProxy.at(chainContracts.system.voteProxy);
    // return;
    var booster = await Booster.at(chainContracts.system.booster);
 
    var cvx = await IERC20.at(chainContracts.system.cvx);

    let rewardManager = await RewardManager.at(chainContracts.system.rewardManager);
    
    let rewardHook = await PoolRewardHook.at(chainContracts.system.rewardHook);
    

    console.log("\n\n --- deployed ----")

    /////// set up pool

    console.log("\n\n >>>> add pool >>>>")
    //tricrypto
    let gauge = await IGauge.at("0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f");
    let curvelp = await IERC20.at("0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2");
    let curvepool = "0x960ea3e3C7FB317332d990873d354E18d7645590";
    let curvePoolFactory = "0xabC000d88f23Bb45525E447528DBF656A9D55bf5";


    await booster.addPool(curvelp.address, gauge.address, curvePoolFactory,{from:deployer});
    console.log("pool added");
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);

    var poolInfo = await booster.poolInfo(plength-1);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    var curvelpCheck = await ERC20.at(poolInfo.lptoken);
    console.log("curve lp token: ")
    console.log("address: " +curvelpCheck.address);
    await curvelpCheck.name().then(a=>console.log("name = " +a))
    await curvelpCheck.symbol().then(a=>console.log("symbol = " +a))
    await curvelpCheck.decimals().then(a=>console.log("decimals = " +a))


    var rewardsTokenCheck = await ERC20.at(poolInfo.rewards);
    console.log("rewards token: ")
    console.log("address: " +rewardsTokenCheck.address);
    await rewardsTokenCheck.name().then(a=>console.log("name = " +a))
    await rewardsTokenCheck.symbol().then(a=>console.log("symbol = " +a))
    await rewardsTokenCheck.decimals().then(a=>console.log("decimals = " +a))


    var rpool = await ConvexRewardPool.at(poolInfo.rewards);
    console.log("rewards pool info: ");
    console.log("address: " +rpool.address);
    await rpool.curveGauge().then(a=>console.log("curveGauge = " +a));
    await rpool.convexStaker().then(a=>console.log("convexStaker = " +a));
    await rpool.convexBooster().then(a=>console.log("convexBooster = " +a));
    await rpool.convexPoolId().then(a=>console.log("convexPoolId = " +a));
    await rpool.totalSupply().then(a=>console.log("totalSupply = " +a));
    await rpool.rewardHook().then(a=>console.log("rewardHook = " +a));
    await rpool.crv().then(a=>console.log("crv = " +a));
    await rpool.rewardLength().then(a=>console.log("rewardLength = " +a));
    await rpool.rewards(0).then(a=>console.log("rewards(0) = " +JSON.stringify(a) ));

    console.log("\n\n --- pool initialized ----");

    //transfer lp tokens
    let lpHolder = "0x555766f3da968ecbefa690ffd49a2ac02f47aa5f";
    await unlockAccount(lpHolder);
    await curvelp.transfer(userA,web3.utils.toWei("100.0", "ether"),{from:lpHolder,gasPrice:0});
    console.log("lp tokens transfered");

    var lpbalance = await curvelp.balanceOf(userA);
    console.log("lp balance: " +lpbalance);



    console.log("\n\n >>> extra rewards >>>");
    

    await rewardManager.setPoolRewardToken(rpool.address, cvx.address, {from:deployer});
    console.log("set reward on pool");
    await rpool.rewardLength().then(a=>console.log("reward length: "+a))

    var extrapool = await ExtraRewardPool.new(booster.address,{from:deployer});
    await extrapool.initialize(cvx.address,{from:deployer});
    console.log("extra pool at " +extrapool.address);

    await rewardManager.setRewardDistributor(extrapool.address, deployer, true, {from:deployer} );
    console.log("set reward distributor")

    await cvx.approve(extrapool.address, web3.utils.toWei("100000000.0", "ether"), {from:deployer});
    console.log("distributor approval")

    await extrapool.queueNewRewards(web3.utils.toWei("1000.0", "ether"), {from:deployer} );
    console.log("rewards queued");

    await extrapool.periodFinish().then(a=>console.log("periodFinish is: " +a))
    await extrapool.rewardRate().then(a=>console.log("rewardRate is: " +a))

    await rewardManager.setPoolWeight(extrapool.address, rpool.address, web3.utils.toWei("1.0", "ether"), {from:deployer});
    console.log("set weight");
    await extrapool.balanceOf(rpool.address).then(a=>console.log("weight of pool: " +a))

    await rewardManager.setPoolRewardContract(rpool.address, rewardHook.address, extrapool.address, {from:deployer});
    console.log("added reward contract to hook for given pool");

    return;
  });
});


