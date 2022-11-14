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
const PoolUtilities = artifacts.require("PoolUtilities");

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

  if(NETWORK == "debugArb" || NETWORK == "mainnetArb"){
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
    // await web3.eth.sendTransaction({from:userA, to:deployer, value:web3.utils.toWei("10.0", "ether") });
    // console.log("sent eth to deployer");

    console.log("\n\n >>>> deploy system >>>>")

    //system
    var usingproxy;
    var found = false;
    while(!found){
      var newproxy = await VoterProxy.new({from:deployer});
      console.log("deployed proxy to " +newproxy.address);
      if(newproxy.address.toLowerCase() == voteproxy.toLowerCase()){
        found=true;
        usingproxy = newproxy;
        console.log("proxy deployed to proper address");
      }
    }

    console.log("using proxy: " +usingproxy.address);

    //deploy booster
    var mainnetbooster = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31";
    var booster;
    found = false;
    while(!found){
      booster = await Booster.new(usingproxy.address,{from:deployer});
      console.log("deployed booster to " +booster.address);
      if(booster.address.toLowerCase() == mainnetbooster.toLowerCase()){
        found=true;
        console.log("booster proper address");
      }
    }
    
    console.log("final booster at: " +booster.address);

    //set proxy operator
    await usingproxy.setOperator(deployer,{from:deployer}).catch(a=>console.log("operator must have isShutdown -> " +a));
    await usingproxy.setOperator(booster.address,{from:deployer});
    console.log("set voterproxy operator");

    //deploy proxy factory
    let pfactory = await ProxyFactory.new({from:deployer});
    console.log("pfactory at: " +pfactory.address);

    //deploy factories
    // let tokenFactory = await TokenFactory.new(booster.address, pfactory.address,{from:deployer});
    // console.log("token factory at: " +tokenFactory.address);

    // let tokenImp = await DepositToken.new(booster.address,{from:deployer});
    // console.log("deposit token impl: " +tokenImp.address);
    // await tokenFactory.setImplementation(tokenImp.address,{from:deployer});
    // console.log("token impl set");

    let rewardHook = await PoolRewardHook.new(booster.address, {from:deployer});
    console.log("reward hook: " +rewardHook.address);

    var dummytoken = await DummyToken.new("DummyToken","DT", {from:deployer});
    console.log("dummy cvx token at " +dummytoken.address);

    let rewardManager = await RewardManager.new(booster.address, dummytoken.address, {from:deployer});
    console.log("reward manager: " +rewardManager.address);
    await rewardManager.setPoolHook(rewardHook.address, {from:deployer});
    await rewardManager.rewardHook().then(a=>console.log("hook set to " +a))

    await booster.setRewardManager(rewardManager.address, {from:deployer});
    await booster.rewardManager().then(a=>console.log("reward manager set to " +a));

    let rewardFactory = await RewardFactory.new(booster.address, usingproxy.address, pfactory.address,{from:deployer});
    console.log("reward factory at: " +rewardFactory.address);

    let rewardImp = await ConvexRewardPool.new({from:deployer});
    console.log("reward pool impl: " +rewardImp.address);
    await rewardFactory.setImplementation(rewardImp.address,{from:deployer});
    console.log("reward impl set");

    // await booster.setRewardFactory(rewardFactory.address, tokenFactory.address,{from:deployer});
    await booster.setRewardFactory(rewardFactory.address, {from:deployer});
    console.log("booster reward factory set");

    let feedeposit = await FeeDeposit.new(deployer);
    console.log("fee deposit at: " +feedeposit.address);
    await booster.setFeeDeposit(feedeposit.address, {from:deployer});
    console.log("fee deposit set on booster");

    let poolUtil = await PoolUtilities.new(booster.address, crv.address);
    console.log("poolUtil: " +poolUtil.address);

    console.log("\n\n --- deployed ----")

    /////// set up pool

    console.log("\n\n >>>> add pool >>>>")
    //tricrypto
    let gauge = await IGauge.at("0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f");
    let curvelp = await IERC20.at("0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2");
    let curvepool = "0x960ea3e3C7FB317332d990873d354E18d7645590";
    let curvePoolFactory = "0xabC000d88f23Bb45525E447528DBF656A9D55bf5";

    await booster.setFactoryCrv(curvePoolFactory, crv.address, {from:deployer});
    console.log("set crv address for factory " +curvePoolFactory);

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
    // await rewardsTokenCheck.initialize(poolInfo.lptoken).catch(a=>console.log("catch reinit on deposit token: " +a))


    var rpool = await ConvexRewardPool.at(poolInfo.rewards);
    console.log("rewards pool info: ");
    console.log("address: " +rpool.address);
    await rpool.curveGauge().then(a=>console.log("curveGauge = " +a));
    await rpool.convexStaker().then(a=>console.log("convexStaker = " +a));
    await rpool.convexBooster().then(a=>console.log("convexBooster = " +a));
    // await rpool.convexToken().then(a=>console.log("convexToken = " +a));
    await rpool.convexPoolId().then(a=>console.log("convexPoolId = " +a));
    await rpool.totalSupply().then(a=>console.log("totalSupply = " +a));
    await rpool.rewardHook().then(a=>console.log("rewardHook = " +a));
    await rpool.crv().then(a=>console.log("crv = " +a));
    await rpool.rewardLength().then(a=>console.log("rewardLength = " +a));
    await rpool.rewards(0).then(a=>console.log("rewards(0) = " +JSON.stringify(a) ));
    //try reinit
    await rpool.initialize(addressZero,addressZero,addressZero,addressZero,addressZero,0).catch(a=>console.log("catch reinit on reward contract: " +a))

    console.log("\n\n --- pool initialized ----");

    ////  user staking

    console.log("\n\n >>>> simulate staking >>>>");
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))
    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));

    
    // await gauge.claimable_tokens.call(userZ).then(a=>console.log("earned: " +a ));
    // await advanceTime(3600);
    // await gauge.claimable_tokens.call(userZ).then(a=>console.log("earned: " +a ));

    // return;

    //transfer lp tokens
    let lpHolder = "0x555766f3da968ecbefa690ffd49a2ac02f47aa5f";
    await unlockAccount(lpHolder);
    await curvelp.transfer(userA,web3.utils.toWei("100.0", "ether"),{from:lpHolder,gasPrice:0});
    console.log("lp tokens transfered");

    var lpbalance = await curvelp.balanceOf(userA);
    console.log("lp balance: " +lpbalance);

    await curvelp.approve(booster.address,web3.utils.toWei("1000000.0", "ether"), {from:userA} );
    console.log("approved lp to booster");

    await booster.depositAll(4, {from:userA}).catch(a=>console.log("caught bad pid: " +a));
    var tx = await booster.deposit(0, web3.utils.toWei("10", "ether"), {from:userA});
    // var tx = await booster.depositAll(0, {from:userA});
    console.log("deposit and staked in booster: " +tx.receipt.gasUsed);

    await rpool.balanceOf(userA).then(a=>console.log("balance in rewards: " +a))
    await rpool.totalSupply().then(a=>console.log("rewards totalSupply: " +a));
    await gauge.totalSupply().then(a=>console.log("gauge total supply: " +a))
    await gauge.balanceOf(voteproxy).then(a=>console.log("gauge balanceOf convex: " +a))
    await gauge.working_balances(voteproxy).then(a=>console.log("gauge working_balances convex: " +a))
    await gauge.working_supply().then(a=>console.log("gauge working_supply: " +a))


    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))

    //claim for other
    await rpool.methods['getReward(address)'](userA, {from:userB});
    console.log("claimed 1 (user b claims for a)");
    
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))
    
    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));

    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    await time.latest().then(a=>console.log("block time: " +a));
    await advanceTime(3600);
    await time.latest().then(a=>console.log("block time: " +a));
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));

     //claim to self
    await rpool.methods['getReward(address)'](userA, {from:userA});
    console.log("claimed 2");

    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));

    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    await advanceTime(3600);
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));

    //claim to self
    await rpool.methods['getReward(address)'](userA, {from:userA});
    console.log("claimed 3");

    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))
    await crv.balanceOf(booster.address).then(a=>console.log("crv on booster: " +a))


    await crv.balanceOf(feedeposit.address).then(a=>console.log("crv on fee deposit: " +a))

    // await booster.processFees();
    // console.log("fees processed")
    console.log("(fees auto sent to deposit and not booster)")

    await crv.balanceOf(booster.address).then(a=>console.log("crv on fee booster: " +a))
    await crv.balanceOf(feedeposit.address).then(a=>console.log("crv on fee deposit: " +a))

    await advanceTime(day);
    console.log("reward fowarding...")


    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet A: " +a))

    //claim and forward
    await rpool.methods['getReward(address,address)'](userA, userB, {from:userB}).catch(a=>console.log("revert if not owner: " +a));
    await rpool.methods['getReward(address,address)'](userA, userB, {from:userA});
    console.log("claimed & forwarded");
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));

    await crv.balanceOf(userA).then(a=>console.log("crv on wallet A: " +a))
    await crv.balanceOf(userB).then(a=>console.log("crv on wallet B: " +a))

    console.log("\n\n --- staking and rewards complete ----");


    console.log("\n\n >>> extra rewards >>>");
    
    await dummytoken.mint(deployer,web3.utils.toWei("1000000.0", "ether"),{from:deployer});
    console.log("minted")

    await rpool.rewardLength().then(a=>console.log("reward length: "+a))
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));


    await rewardManager.setPoolRewardToken(rpool.address, dummytoken.address, {from:deployer});
    console.log("set reward on pool");
    await rpool.rewardLength().then(a=>console.log("reward length: "+a))

    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));


    var extrapool = await ExtraRewardPool.new(booster.address,{from:deployer});
    await extrapool.initialize(dummytoken.address,{from:deployer});
    console.log("extra pool at " +extrapool.address);
    await extrapool.rewardManager().then(a=>console.log("manager is: " +a))
    await extrapool.rewardToken().then(a=>console.log("reward is: " +a))
    await extrapool.periodFinish().then(a=>console.log("periodFinish is: " +a))
    await extrapool.rewardRate().then(a=>console.log("rewardRate is: " +a))

    await rewardManager.setRewardDistributor(extrapool.address, deployer, true, {from:deployer} );
    console.log("set reward distributor")

    await dummytoken.approve(extrapool.address, web3.utils.toWei("100000000.0", "ether"), {from:deployer});
    console.log("distributor approval")

    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));
    await poolUtil.externalRewardContracts(0).then(a=>console.log("externalRewardContracts: " +a));
    await poolUtil.aggregateExtraRewardRates(0).then(a=>console.log("aggregateExtraRewardRates: " +JSON.stringify(a)));


    // await dummytoken.transfer(extrapool.address, web3.utils.toWei("1000.0", "ether"), {from:deployer} );
    await extrapool.queueNewRewards(web3.utils.toWei("0.0", "ether"), {from:userA} ).catch(a=>console.log("revert on non-distributor: " +a));
    await extrapool.queueNewRewards(web3.utils.toWei("1000.0", "ether"), {from:deployer} );
    console.log("rewards queued");

    await extrapool.periodFinish().then(a=>console.log("periodFinish is: " +a))
    await extrapool.rewardRate().then(a=>console.log("rewardRate is: " +a))

    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));
    await poolUtil.externalRewardContracts(0).then(a=>console.log("externalRewardContracts: " +a));
    await poolUtil.aggregateExtraRewardRates(0).then(a=>console.log("aggregateExtraRewardRates: " +JSON.stringify(a)));

    await extrapool.balanceOf(rpool.address).then(a=>console.log("weight of pool: " +a))
    await rewardManager.setPoolWeight(extrapool.address, rpool.address, web3.utils.toWei("1.0", "ether"), {from:deployer});
    console.log("set weight");
    await extrapool.balanceOf(rpool.address).then(a=>console.log("weight of pool: " +a))

    await rewardManager.setPoolRewardContract(rpool.address, rewardHook.address, extrapool.address, {from:deployer});
    console.log("added reward contract to hook for given pool");


    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));
    await poolUtil.externalRewardContracts(0).then(a=>console.log("externalRewardContracts: " +a));
    await poolUtil.aggregateExtraRewardRates(0).then(a=>console.log("aggregateExtraRewardRates: " +JSON.stringify(a) ));

    //add more to staked
    await booster.deposit(0, web3.utils.toWei("10.0", "ether"), {from:userA});
    console.log("deposit increased")
    await poolUtil.aggregateExtraRewardRates(0).then(a=>console.log("aggregateExtraRewardRates: " +JSON.stringify(a) ));

    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    await advanceTime(day);
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    await advanceTime(day);
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    // await advanceTime(day);
    // await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    // await advanceTime(day);
    // await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));

    await crv.balanceOf(userA).then(a=>console.log("crv on wallet A: " +a))
    await dummytoken.balanceOf(userA).then(a=>console.log("dummytoken on wallet A: " +a))
    await dummytoken.balanceOf(extrapool.address).then(a=>console.log("dummytoken on extrapool: " +a))
    await dummytoken.balanceOf(rpool.address).then(a=>console.log("dummytoken on rpool: " +a))
    await rpool.methods['getReward(address)'](userA, {from:userA});
    console.log("claimed");
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet A: " +a))
    await dummytoken.balanceOf(userA).then(a=>console.log("dummytoken on wallet A: " +a))

    console.log("\n\n --- extra rewards complete ----");


    console.log("\n\n >>> stake transfer >>>\n");

    await rpool.balanceOf(userA).then(a=>console.log("balance of A: " +a))
    await rpool.balanceOf(userB).then(a=>console.log("balance of B: " +a))
    await rpool.earned.call(userA).then(a=>console.log("earned A: " +JSON.stringify(a) ));
    await rpool.earned.call(userB).then(a=>console.log("earned B: " +JSON.stringify(a) ));
    await advanceTime(day);
    await rpool.earned.call(userA).then(a=>console.log("earned A: " +JSON.stringify(a) ));
    await rpool.earned.call(userB).then(a=>console.log("earned B: " +JSON.stringify(a) ));

    var rbal = await rpool.balanceOf(userA);
    console.log("\n\ntransfer to user B: " +rbal);
    await rpool.transfer(userB, rbal, {from:userA});

    await rpool.balanceOf(userA).then(a=>console.log("balance of A: " +a))
    await rpool.balanceOf(userB).then(a=>console.log("balance of B: " +a))
    console.log("\n\n");

    await rpool.earned.call(userA).then(a=>console.log("earned A: " +JSON.stringify(a) ));
    await rpool.earned.call(userB).then(a=>console.log("earned B: " +JSON.stringify(a) ));
    await advanceTime(day);
    await rpool.earned.call(userA).then(a=>console.log("earned A: " +JSON.stringify(a) ));
    await rpool.earned.call(userB).then(a=>console.log("earned B: " +JSON.stringify(a) ));

    await advanceTime(day);
    await rpool.earned.call(userA).then(a=>console.log("earned A: " +JSON.stringify(a) ));
    await rpool.earned.call(userB).then(a=>console.log("earned B: " +JSON.stringify(a) ));

    console.log("\n\n --- stake transfer complete ----");


    console.log("\n\n >>> withdraw >>>");


    await rpool.balanceOf(userA).then(a=>console.log("balance A in rewards: " +a))
    await rpool.balanceOf(userB).then(a=>console.log("balance B in rewards: " +a))
    await rpool.totalSupply().then(a=>console.log("rewards totalSupply: " +a));
    await curvelp.balanceOf(userB).then(a=>console.log("curve lp balance of B: " +a))
    await rpool.withdrawAll(true,{from:userB});
    console.log("withdrawn");
    await rpool.balanceOf(userB).then(a=>console.log("balance in rewardsof B: " +a))
    await rpool.totalSupply().then(a=>console.log("rewards totalSupply: " +a));
    await curvelp.balanceOf(userB).then(a=>console.log("curve lp balance of B: " +a))

    console.log("\n\n --- withdraw complete ----");

    console.log("\n\n >>> shutdown >>>");

    await curvelp.balanceOf(userA).then(a=>console.log("curve lp balance of A: " +a))
    //deposit
    for(var i = 0; i < 10; i++){
      await booster.deposit(0, web3.utils.toWei("1.0", "ether"), {from:userA});
      console.log("deposited " +i);
    }

    //try create same pool
    console.log("..try create same pool")
    await booster.addPool(curvelp.address, gauge.address, curvePoolFactory,{from:deployer}).catch(a=>console.log("revert: " +a));
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);

    //shutdown
    await booster.shutdownPool(0,{from:deployer});
    console.log("shutdown pool 0 complete");
    var poolInfo = await booster.poolInfo(0);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    //create new pool
    console.log("..try recreate same pool")
    await booster.addPool(curvelp.address, gauge.address, curvePoolFactory,{from:deployer}).catch(a=>console.log("revert: " +a));
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);
    var poolInfo = await booster.poolInfo(plength-1);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    //deposit
    await booster.deposit(1, web3.utils.toWei("10.0", "ether"), {from:userA});
    console.log("deposited into new pool");

    //shutdown 2
    await booster.shutdownPool(1,{from:deployer});
    console.log("shutdown pool 1 complete");
    var poolInfo = await booster.poolInfo(1);
    var newrewardpool = await ConvexRewardPool.at(poolInfo.rewards);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    //withdraw proper amounts from both pids
    await curvelp.balanceOf(userA).then(a=>console.log("curve lp balance of A: " +a))
    await rpool.balanceOf(userA).then(a=>console.log("balance A in pool 0: " +a))
    await newrewardpool.balanceOf(userA).then(a=>console.log("balance A in pool 1: " +a))
    await curvelp.balanceOf(booster.address).then(a=>console.log("curve lp on booster: " +a))
    await booster.shutdownBalances(0).then(a=>console.log("shutdown balances of pid 0: " +a))
    await booster.shutdownBalances(1).then(a=>console.log("shutdown balances of pid 1: " +a))

    await rpool.withdrawAll(true,{from:userA});
    console.log("withdrawn 0");
    await newrewardpool.withdrawAll(true,{from:userA});
    console.log("withdrawn 1");


    await curvelp.balanceOf(userA).then(a=>console.log("curve lp balance of A: " +a))
    await rpool.balanceOf(userA).then(a=>console.log("balance A in pool 0: " +a))
    await newrewardpool.balanceOf(userA).then(a=>console.log("balance A in pool 1: " +a))
    await curvelp.balanceOf(booster.address).then(a=>console.log("curve lp on booster: " +a))
    await booster.shutdownBalances(0).then(a=>console.log("shutdown balances of pid 0: " +a))
    await booster.shutdownBalances(1).then(a=>console.log("shutdown balances of pid 1: " +a))

    await rpool.withdraw(web3.utils.toWei("1.0", "ether"),true,{from:userA}).catch(a=>console.log("revert 0: no more deposited balance"));
    await newrewardpool.withdraw(web3.utils.toWei("1.0", "ether"),true,{from:userA}).catch(a=>console.log("revert 1: no more deposited balance"));


    console.log("\n\ncreate new pool")
    await booster.addPool(curvelp.address, gauge.address, curvePoolFactory,{from:deployer}).catch(a=>console.log("revert: " +a));
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);
    var poolInfo = await booster.poolInfo(plength-1);
    var newrewardpool = await ConvexRewardPool.at(poolInfo.rewards);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    //deposit
    await booster.deposit(2, web3.utils.toWei("10.0", "ether"), {from:userA});
    console.log("deposited into new pool");
    await newrewardpool.balanceOf(userA).then(a=>console.log("balance A in pool 2: " +a))

    await booster.isShutdown().then(a=>console.log("is shutdown? " +a));
    await booster.shutdownSystem({from:deployer});
    console.log("shutdown system")
    await booster.isShutdown().then(a=>console.log("is shutdown? " +a));

    console.log("try deposit again");
    await booster.deposit(2, web3.utils.toWei("10.0", "ether"), {from:userA}).catch(a=>console.log("catch: " +a));
    
    var poolInfo = await booster.poolInfo(plength-1);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    console.log("try set operator");
    await usingproxy.setOperator(deployer,{from:deployer}).catch(a=>console.log("catch: " +a));

    let newbooster = await Booster.new(usingproxy.address,{from:deployer});
    console.log("deploy new booster at: " +newbooster.address);

    await usingproxy.setOperator(newbooster.address,{from:userA}).catch(a=>console.log("catch: " +a ));
    await usingproxy.setOperator(newbooster.address,{from:deployer});
    await usingproxy.operator().then(a=>console.log("set operator: " +a))

    console.log("\n\n --- withdraw complete ----");


    console.log("\n\n >>> auth >>>");

    await usingproxy.owner().then(a=>console.log("proxy owner: " +a))
    await usingproxy.pendingOwner().then(a=>console.log("proxy pendingOwner: " +a))
    await usingproxy.setPendingOwner(userZ,{from:userA}).catch(a=>console.log("set pending auth: " +a));
    await usingproxy.setPendingOwner(userZ,{from:deployer});
    console.log("set pending")
    await usingproxy.owner().then(a=>console.log("proxy owner: " +a))
    await usingproxy.pendingOwner().then(a=>console.log("proxy pendingOwner: " +a))

    await usingproxy.acceptPendingOwner({from:userA}).catch(a=>console.log("accept auth"));
    await unlockAccount(userZ);
    await usingproxy.acceptPendingOwner({from:userZ, gasPrice:0});

    await usingproxy.owner().then(a=>console.log("proxy owner: " +a))
    await usingproxy.pendingOwner().then(a=>console.log("proxy pendingOwner: " +a))

    await curvelp.allowance(usingproxy.address, userZ).then(a=>console.log("allowance check: " +a));
    var data = curvelp.contract.methods.approve(userZ,web3.utils.toWei("1.0","ether")).encodeABI();
    await usingproxy.execute(curvelp.address,0,data,{from:userA}).catch(a=>console.log("execute auth: " +a))
    await unlockAccount(newbooster.address);
    await usingproxy.execute(curvelp.address,0,data,{from:newbooster.address,gasPrice:0});
    await curvelp.allowance(usingproxy.address, userZ).then(a=>console.log("allowance check: " +a));

    await usingproxy.claimRewards(gauge.address,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))
    await usingproxy.claimCrv(gauge.address,addressZero,addressZero,addressZero,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))
    await usingproxy.withdrawAll(gauge.address,addressZero,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))
    await usingproxy.withdraw(gauge.address,addressZero,0,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))
    await usingproxy.rescue(gauge.address,addressZero,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))
    await usingproxy.deposit(gauge.address,addressZero,0,{from:userA}).catch(a=>console.log("proxy auth fail: " +a))

    console.log("\n\n --- auth complete ----");


    return;
  });
});


