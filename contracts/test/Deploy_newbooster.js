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
const PoolUtilities = artifacts.require("PoolUtilities");
const PoolManager = artifacts.require("PoolManager");
const cvxToken = artifacts.require("cvxToken");

const IERC20 = artifacts.require("IERC20");
const ERC20 = artifacts.require("ERC20");


const unlockAccount = async (address) => {
  let NETWORK = config.network;
  if(!NETWORK.includes("debug")){
    return null;
  }
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "hardhat_impersonateAccount",
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

const setNoGas = async () => {
  let NETWORK = config.network;
  if(!NETWORK.includes("debug")){
    return null;
  }
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "hardhat_setNextBlockBaseFeePerGas",
        params: ["0x0"],
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

const send = payload => {
  if (!payload.jsonrpc) payload.jsonrpc = '2.0';
  if (!payload.id) payload.id = new Date().getTime();

  return new Promise((resolve, reject) => {
    web3.currentProvider.send(payload, (error, result) => {
      if (error) return reject(error);

      return resolve(result);
    });
  });
};

/**
 *  Mines a single block in Ganache (evm_mine is non-standard)
 */
const mineBlock = () => send({ method: 'evm_mine' });

/**
 *  Gets the time of the last block.
 */
const currentTime = async () => {
  const { timestamp } = await web3.eth.getBlock('latest');
  return timestamp;
};

/**
 *  Increases the time in the EVM.
 *  @param seconds Number of seconds to increase the time by
 */
const fastForward = async seconds => {
  // It's handy to be able to be able to pass big numbers in as we can just
  // query them from the contract, then send them back. If not changed to
  // a number, this causes much larger fast forwards than expected without error.
  if (BN.isBN(seconds)) seconds = seconds.toNumber();

  // And same with strings.
  if (typeof seconds === 'string') seconds = parseFloat(seconds);

  await send({
    method: 'evm_increaseTime',
    params: [seconds],
  });

  await mineBlock();
};

const getChainContracts = () => {
  let NETWORK = config.network;//process.env.NETWORK;
  console.log("network: " +NETWORK);
  var contracts = {};

  if(NETWORK == "debugArb" || NETWORK == "mainnetArb"){
    contracts = contractList.arbitrum;
  }
  if(NETWORK == "debugPoly" || NETWORK == "mainnetPoly"){
    contracts = contractList.polygon;
  }
  if(NETWORK == "debugFraxtal" || NETWORK == "mainnetFraxtal"){
    contracts = contractList.fraxtal;
  }


  console.log("using crv: " +contracts.curve.crv);
  return contracts;
}

const advanceTime = async (secondsElaspse) => {
  await fastForward(secondsElaspse);
  console.log("\n  >>>>  advance time " +(secondsElaspse/86400) +" days  >>>>\n");
}
const day = 86400;

contract("Deploy System and test staking/rewards", async accounts => {
  it("should deploy contracts and test various functions", async () => {

    let deployer = "0x947B7742C403f20e5FaCcDAc5E092C943E7D0277";
    let multisig = "0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB";
    let addressZero = "0x0000000000000000000000000000000000000000"

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
    await unlockAccount(deployer);

    console.log("\n\n >>>> deploy system >>>>")
    await web3.eth.getGasPrice().then(a=>console.log("gas price: " +a))

    var currentNonce = await web3.eth.getTransactionCount(deployer);
    console.log("nonce: "+currentNonce);

    //system
    var usingproxy = await VoterProxy.at(chainContracts.system.voteProxy);
    let pfactory = await ProxyFactory.at(chainContracts.system.proxyFactory);
    var cvx = await cvxToken.at(chainContracts.system.cvx);

    // return;
    var oldbooster = await Booster.at(chainContracts.system.booster);
    console.log("old booster at: " +oldbooster.address)

    //new booster
    var booster = await Booster.new(usingproxy.address,{from:deployer});
    console.log("new booster at: " +booster.address)
    chainContracts.system.booster = booster.address;

    //shutdown
    await oldbooster.shutdownSystem({from:deployer});
    console.log("shutdown old")

    //set proxy operator to new booster
    await usingproxy.setOperator(booster.address,{from:deployer});
    console.log("set voterproxy operator");

    //new reward hook
    let rewardHook = await PoolRewardHook.new(booster.address, {from:deployer});
    chainContracts.system.rewardHook = rewardHook.address;
    console.log("reward hook: " +rewardHook.address);

    //new reward manager
    let rewardManager = await RewardManager.new(booster.address, cvx.address, rewardHook.address, {from:deployer});
    chainContracts.system.rewardManager = rewardManager.address;
    console.log("reward manager: " +rewardManager.address);

    //set hook
    await rewardManager.setPoolHook(rewardHook.address, {from:deployer});
    await rewardManager.rewardHook().then(a=>console.log("hook set to " +a))

    //set reward manager
    await booster.setRewardManager(rewardManager.address, {from:deployer});
    await booster.rewardManager().then(a=>console.log("reward manager set to " +a));

    //set crv gauge factory
    await booster.setFactoryCrv(chainContracts.curve.gaugeFactory, chainContracts.curve.crv, {from:deployer});
    console.log("set factory crv");

    let cvxRewards = await ExtraRewardPool.new(booster.address,{from:deployer});
    await cvxRewards.initialize(cvx.address,{from:deployer});
    console.log("cvx rewards at: " +cvxRewards.address);
    chainContracts.system.cvxIncentives = cvxRewards.address;

    let poolManager = await PoolManager.new(booster.address, cvxRewards.address, {from:deployer});
    await booster.setPoolManager(poolManager.address,{from:deployer});
    chainContracts.system.poolManager = poolManager.address;
    console.log("set pool manager to booster");

    await rewardManager.setPoolRewardRole(poolManager.address, true, {from:deployer});
    console.log("give pool manager reward role");

    await rewardManager.setRewardDistributor(cvxRewards.address, deployer, true, {from:deployer} );
    console.log("set reward distributor")

    //new reward factory
    let rewardFactory = await RewardFactory.new(booster.address, usingproxy.address, pfactory.address,{from:deployer});
    chainContracts.system.rewardFactory = rewardFactory.address;
    console.log("reward factory at: " +rewardFactory.address);

    // let rewardImp = await ConvexRewardPool.new({from:deployer});
    let rewardImp = await ConvexRewardPool.at(chainContracts.system.rewardPool);
    console.log("reward pool impl: " +rewardImp.address);
    await rewardFactory.setImplementation(rewardImp.address,{from:deployer});
    console.log("reward impl set");

    await booster.setRewardFactory(rewardFactory.address, {from:deployer});
    console.log("booster reward factory set");

    // let feedeposit = await FeeDeposit.new(deployer);
    let feedeposit = await FeeDeposit.at(chainContracts.system.feeDeposit);
    console.log("fee deposit at: " +feedeposit.address);
    await booster.setFeeDeposit(feedeposit.address, {from:deployer});
    console.log("fee deposit set on booster");

    let poolUtil = await PoolUtilities.new(booster.address, chainContracts.curve.crv);
    chainContracts.system.poolUtilities = poolUtil.address;
    console.log("poolUtil: " +poolUtil.address);

    console.log("\n\n --- deployed ----");

    console.log(chainContracts);
    if(config.network == "debugArb" || config.network == "mainnetArb"){
      contractList.arbitrum = chainContracts;
    }
    if(config.network == "debugPoly" || config.network == "mainnetPoly"){
      contractList.polygon = chainContracts;
    }
    if(config.network == "debugFraxtal" || config.network == "mainnetFraxtal"){
      contractList.fraxtal = chainContracts;
    }
    if(config.network.includes("mainnet")){
      console.log("updating contract json...");
      jsonfile.writeFileSync("./contracts.json", contractList, { spaces: 4 });
    }
    jsonfile.writeFileSync("./contracts.json", contractList, { spaces: 4 });

    //deploy initial pools
    console.log("deploy initial pools...");
    await poolManager.addPool("0x9ccc509a5b4869bac6be86e79ea00c25942852f4",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0x98a6c35546be6f7c545c99efb48f4673ed2c99fc",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0xaa6ddba00de48d41e41543ef0a78ab31aae4de8d",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0xe049aa6fbd64210bdeddc15f5a861084e6ee8b57",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0x64100c172d5dc8007e3ee701ecd99468619b6583",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0x6d8bc3cfbd1b62f3fb0e5517ebca283af1185576",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0xfe2afbe02d800836d2c7081eef2a4a8408f90488",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0x72bd89f2e3470fa5d188cf04eda17e8145eb4bf1",chainContracts.curve.gaugeFactory, {from:deployer});
    await poolManager.addPool("0xd1d981ddd0c9a0469e7d8cee877f83b5877d7260",chainContracts.curve.gaugeFactory, {from:deployer});


    console.log("done");
    return;
  });
});


