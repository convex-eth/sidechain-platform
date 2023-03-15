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

    await poolManager.shutdownPool(0,{from:deployer});
    console.log("shudown pool");
    await poolManager.shutdownPool(1,{from:deployer});
    console.log("shudown pool");
    await poolManager.shutdownPool(2,{from:deployer});
    console.log("shudown pool");
    await poolManager.shutdownPool(3,{from:deployer});
    console.log("shudown pool");
    await poolManager.shutdownPool(4,{from:deployer});
    console.log("shudown pool");
    await poolManager.shutdownPool(5,{from:deployer});
    console.log("shudown pool");

    for(g in gauges){
      console.log("\n\nadd pool " +g +" with gauge: " +gauges[g]);
      await poolManager.addPool(gauges[g], chainContracts.curve.gaugeFactory, {from:deployer});
      console.log("pool created");
    }


    console.log("done");

    return;
  });
});


