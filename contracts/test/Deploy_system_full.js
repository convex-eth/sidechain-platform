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

    let chainContracts = getChainContracts();
    let deployer = chainContracts.system.deployer;
    let multisig = chainContracts.system.multisig;
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

    console.log("using gas price: " +config.network_config.gasPrice);

    await unlockAccount(deployer);

    console.log("\n\n >>>> deploy system >>>>")

    await web3.eth.getGasPrice().then(a=>console.log("gas price: " +a))

    var currentNonce = await web3.eth.getTransactionCount(deployer);
    console.log("nonce: "+currentNonce);

    //system
    var found = false;
    while(!found){
      await web3.eth.getTransactionCount(deployer).then(a=>console.log("nonce: " +a));
      // var newproxy = await VoterProxy.new({from:deployer,gasPrice:10000000});
      var newproxy = await VoterProxy.new({from:deployer});
      console.log("deployed proxy to " +newproxy.address);
      if(newproxy.address.toLowerCase() == voteproxy.toLowerCase()){
        found=true;
        console.log("proxy deployed to proper address");
      }
    }

    var currentNonce = await web3.eth.getTransactionCount(deployer);
    console.log("nonce: "+currentNonce);
    while(currentNonce < 10){
      await web3.eth.sendTransaction({from:deployer,to:deployer,value:0});
      currentNonce = await web3.eth.getTransactionCount(deployer);
      console.log("nonce: "+currentNonce);
    }

    //deploy cvx to same address in case needed? might as well deploy to same address even if not used...
    var cvx = await cvxToken.new("Convex Token","CVX",chainContracts.system.voteProxy,{from:deployer});
    chainContracts.system.cvx = cvx.address;
    console.log("cvx: " +chainContracts.system.cvx);
    await cvx.name().then(a=>console.log("name " +a))
    await cvx.symbol().then(a=>console.log("symbol " +a))
    await cvx.owner().then(a=>console.log("owner " +a))

    //system
    var usingproxy = await VoterProxy.at(chainContracts.system.voteProxy);

    // return;
    var booster;// = await Booster.new(usingproxy.address);
    var originalBooster = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31";
    var found = false;
    while(!found){
      booster = await Booster.new(usingproxy.address,{from:deployer});
      console.log("deployed booster to " +booster.address);
      if(booster.address.toLowerCase() == originalBooster.toLowerCase()){
        found=true;
        console.log("booster deployed to original address");
      }
    }
    chainContracts.system.booster = booster.address;
    console.log("using booster at: " +booster.address)

    currentNonce = await web3.eth.getTransactionCount(deployer);
    console.log("nonce: "+currentNonce);
    while(currentNonce < 17){
      await web3.eth.sendTransaction({from:deployer,to:deployer,value:0});
      currentNonce = await web3.eth.getTransactionCount(deployer);
      console.log("nonce: "+currentNonce);
    }

    //deploy cvx to same address in case needed? might as well deploy to same address even if not used...
    var cvxCrv = await cvxToken.new("Convex CRV","cvxCRV",chainContracts.system.voteProxy,{from:deployer});
    chainContracts.system.cvxCrv = cvxCrv.address;
    console.log("cvxCrv: " +chainContracts.system.cvxCrv);
    await cvxCrv.name().then(a=>console.log("name " +a))
    await cvxCrv.symbol().then(a=>console.log("symbol " +a))
    await cvxCrv.owner().then(a=>console.log("owner " +a))

    //set proxy operator
    await usingproxy.setOperator(booster.address,{from:deployer});
    console.log("set voterproxy operator");

    //deploy proxy factory
    let pfactory = await ProxyFactory.new({from:deployer});
    chainContracts.system.proxyFactory = pfactory.address;
    console.log("pfactory at: " +pfactory.address);

    let rewardHook = await PoolRewardHook.new(booster.address, {from:deployer});
    chainContracts.system.rewardHook = rewardHook.address;
    console.log("reward hook: " +rewardHook.address);

    var cvx = await IERC20.at(chainContracts.system.cvx);
    console.log("cvx : " +cvx.address);

    let rewardManager = await RewardManager.new(booster.address, cvx.address, rewardHook.address, {from:deployer});
    chainContracts.system.rewardManager = rewardManager.address;
    console.log("reward manager: " +rewardManager.address);

    await rewardManager.setPoolHook(rewardHook.address, {from:deployer});
    // ///////
    await rewardManager.rewardHook().then(a=>console.log("hook set to " +a))

    await booster.setRewardManager(rewardManager.address, {from:deployer});
    await booster.rewardManager().then(a=>console.log("reward manager set to " +a));

    if(chainContracts.curve.crv != addressZero){
      await booster.setFactoryCrv(chainContracts.curve.gaugeFactory, chainContracts.curve.crv, {from:deployer});
      console.log("set factory crv");
    }

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

    let rewardFactory = await RewardFactory.new(booster.address, usingproxy.address, pfactory.address,{from:deployer});
    chainContracts.system.rewardFactory = rewardFactory.address;
    console.log("reward factory at: " +rewardFactory.address);

    let rewardImp = await ConvexRewardPool.new({from:deployer});
    chainContracts.system.rewardPool = rewardImp.address;
    console.log("reward pool impl: " +rewardImp.address);
    await rewardFactory.setImplementation(rewardImp.address,{from:deployer});
    console.log("reward impl set");

    await booster.setRewardFactory(rewardFactory.address, {from:deployer});
    console.log("booster reward factory set");

    let feedeposit = await FeeDeposit.new(deployer,{from:deployer});
    chainContracts.system.feeDeposit = feedeposit.address;
    console.log("fee deposit at: " +feedeposit.address);
    await booster.setFeeDeposit(feedeposit.address, {from:deployer});
    console.log("fee deposit set on booster");

    if(chainContracts.curve.crv != addressZero){
      let poolUtil = await PoolUtilities.new(booster.address, crv.address,{from:deployer});
      chainContracts.system.poolUtilities = poolUtil.address;
    }else{
      chainContracts.system.poolUtilities = "TODO";
    }
    console.log("poolUtil: " +chainContracts.system.poolUtilities);

    await rewardManager.setRewardDistributor(cvxRewards.address, deployer, true, {from:deployer} );
    console.log("set reward distributor")

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
    jsonfile.writeFileSync("./contracts.json", contractList, { spaces: 4 });

    return;
  });
});


