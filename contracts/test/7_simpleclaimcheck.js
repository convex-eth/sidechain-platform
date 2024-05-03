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
const BoosterOwner = artifacts.require("BoosterOwner");

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
  await time.increase(secondsElaspse);
  await time.advanceBlock();
  console.log("\n  >>>>  advance time " +(secondsElaspse/86400) +" days  >>>>\n");
}
const day = 86400;

contract("Deploy System and test staking/rewards", async accounts => {
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

    
    await unlockAccount(multisig);
    await unlockAccount(deployer);
    console.log("deployer " +deployer);
    console.log("\n\n >>>> deploy simple >>>>")

    var rewardtoken = await IERC20.at("0x912CE59144191C1204E64559FE8253a0e49E6548");
    var pool = await ConvexRewardPool.at("0xBFEE9F3E015adC754066424AEd535313dc764116");
    var holder = "0x99b95c60b2d68db15dffb11a71076a31ccaf1487";
    await unlockAccount(holder);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens before: " +a))
    await pool.claimable_reward(rewardtoken.address,userA).then(a=>console.log("checkpointed claimable: " +a))
    await pool.reward_integral_for(rewardtoken.address,userA).then(a=>console.log("reward_integral_for: " +a))
    await currentTime().then(a=>console.log("time " +a))
    await pool.transfer(userA,web3.utils.toWei("100000.0", "ether"),{from:holder,gasPrice:0})
    await currentTime().then(a=>console.log("time after " +a))
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens after: " +a))
    await pool.claimable_reward(rewardtoken.address,userA).then(a=>console.log("checkpointed claimable: " +a))
    await pool.reward_integral_for(rewardtoken.address,userA).then(a=>console.log("reward_integral_for: " +a))
    await pool.user_checkpoint(userA);
    await pool.claimable_reward(rewardtoken.address,userA).then(a=>console.log("checkpointed claimable: " +a))
    await pool.reward_integral_for(rewardtoken.address,userA).then(a=>console.log("reward_integral_for: " +a))

    await pool.getReward(userA);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens claimed: " +a))
    await advanceTime(day);
    await pool.claimable_reward(rewardtoken.address,userA).then(a=>console.log("checkpointed claimable: " +a))
    await pool.getReward(userA);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens claimed: " +a))
    await advanceTime(day);
    await pool.getReward(userA);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens claimed: " +a))
    await advanceTime(day);
    await pool.getReward(userA);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens claimed: " +a))
    await advanceTime(day);
    await pool.getReward(userA);
    await rewardtoken.balanceOf(userA).then(a=>console.log("tokens claimed: " +a))
    await advanceTime(day);



    return;
  });
});


