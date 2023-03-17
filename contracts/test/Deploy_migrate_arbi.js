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

const IERC20 = artifacts.require("IERC20");
const ERC20 = artifacts.require("ERC20");


const addAccount = async (address) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_addAccount",
        params: [address, "passphrase"],
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

const unlockAccount = async (address) => {
  await addAccount(address);
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "personal_unlockAccount",
        params: [address, "passphrase"],
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
const mineMultiBlock = (blockCnt) => send({ method: 'evm_mine', options:{blocks:blockCnt } });
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

  // await mineBlock();
  await mineMultiBlock(1000);
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

  console.log("using crv: " +contracts.curve.crv);
  return contracts;
}

const advanceTime = async (secondsElaspse) => {
  await time.increase(secondsElaspse);
  await time.advanceBlock();
  console.log("\n  >>>>  advance time " +(secondsElaspse/86400) +" days  >>>>\n");
}
const day = 86400;

contract("Deploy pools", async accounts => {
  it("should deploy contracts and test various functions", async () => {

    let chainContracts = getChainContracts();
    let crv = await IERC20.at(chainContracts.curve.crv);
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

    

    console.log("\n\n >>>> deploy pools >>>>")

    //system
    var usingproxy = await VoterProxy.at(chainContracts.system.voteProxy);

    // return;
    var booster = await Booster.at(chainContracts.system.booster);
    var poolManager = await PoolManager.at(chainContracts.system.poolManager);
    
    var gauges = [
      "0xF2dDF89C04d702369Ab9eF8399Edb99a76e951Ce",
      "0xCE5F24B7A95e9cBa7df4B54E911B4A3Dc8CDAf6f",
      "0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f",
      "0x6339eF8Df0C2d3d3E7eE697E241666a916B81587",
      "0x95285Ea6fF14F80A2fD3989a6bAb993Bd6b5fA13"
      ];

    for(var i = 0; i < 6; i++){
      console.log("--- pool " +i +" ----")
      var pinfo = await booster.poolInfo(i);
      //console.log("pinfo: " +JSON.stringify(pinfo));
      var lp = await ERC20.at(pinfo.lptoken)
      await lp.name().then(a=>console.log("lp token " +a))
      var rewards = await ConvexRewardPool.at(pinfo.rewards);
      await rewards.rewards(0).then(a=>console.log("reward data: " +JSON.stringify(a)))
      await rewards.user_checkpoint(addressZero);
      console.log("checkpoint " +i)
      await rewards.rewards(0).then(a=>console.log("reward data: " +JSON.stringify(a)))
      await poolManager.shutdownPool(i,{from:deployer});
      console.log("shudown pool " +i);
      console.log("\n\n")
    }

    for(g in gauges){
      console.log("\n\nadd pool " +g +" with gauge: " +gauges[g]);
      await poolManager.addPool(gauges[g], chainContracts.curve.gaugeFactory, {from:deployer});
      console.log("pool created");
    }

    console.log("done");


    // console.log(" test withdraw and restake ")

    // var triinfo = await booster.poolInfo(3);
    // var trirewards = await ConvexRewardPool.at(triinfo.rewards);
    // var balance = await trirewards.balanceOf(userZ);//.then(a=>console.log("user z: " +a));
    // console.log("balance: " +balance)
    // await unlockAccount(userZ);
    // await trirewards.withdraw(balance,true,{from:userZ});
    // console.log("withdrawn");
    // var trilp = await IERC20.at(triinfo.lptoken);
    // await trilp.balanceOf(userZ).then(a=>console.log("lp tokens on user z: " +a));


    // var newtriinfo = await booster.poolInfo(8);
    // console.log("pinfo 8: " +JSON.stringify(newtriinfo));
    // var newrewards = await ConvexRewardPool.at(newtriinfo.rewards);
    // await booster.depositAll(8,{from:userZ});
    // await newrewards.balanceOf(userZ).then(a=>console.log("new staked balance: "+a))
    // await newrewards.earned.call(userZ).then(a=>console.log("earned: " +JSON.stringify(a) ));
    // await advanceTime(day);
    // await newrewards.earned.call(userZ).then(a=>console.log("earned: " +JSON.stringify(a) ));
    return;
  });
});


