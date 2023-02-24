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
      "0xda690c2ea49a058a9966c69f46a05bfc225939f4",
      "0x18006c6a7955bf6db72de34089b975f733601660",
      "0x20759f567bb3ecdb55c817c9a1d13076ab215edc",
      "0xbb1b19495b8fe7c402427479b9ac14886cbbaaee",
      "0x8d9649e50a0d1da8e939f800fb926cde8f18b47d",
      "0x8b397084699cc64e429f610f81fac13bf061ef55",
      "0xd1426c391a7cbe9decd302ac9c44e65c3505d1f0",
      "0x82edd50a204d86d90def4dedc4671e9a21145d5e",
      "0x40371aad2a24ed841316ef30938881440fd4426c",
      "0x0e2f214b8f5d0cca011a8298bb907fb62f535160"
      ];

    let poolUtil = await PoolUtilities.at(chainContracts.system.poolUtilities);

    for(g in gauges){
      console.log("\n\nadd pool with gauge: " +gauges[g]);
      await poolManager.addPool(gauges[g], chainContracts.curve.gaugeFactory, {from:deployer});
      console.log("pool created");

      await poolUtil.gaugeRewardRates(g,0).then(a=>console.log("pool gaugeRewardRates: " +JSON.stringify(a)));
    }


    console.log("done");

    return;
  });
});


