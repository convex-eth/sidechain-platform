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
  let NETWORK = config.network;
  if(!NETWORK.includes("debug")){
    return null;
  }
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

    console.log("\n\n >>>> deploy simple >>>>")

    let pool = await ConvexRewardPool.new({from:deployer});
    console.log("pool: " +pool.address);

    let rewardManager = await RewardManager.new(chainContracts.system.booster, chainContracts.system.cvx, chainContracts.system.rewardHook, {from:deployer});
    console.log("rewardManager: " +rewardManager.address);

    var cvx = await IERC20.at(chainContracts.system.cvx);
    console.log("cvx : " +cvx.address);
    
    let cvxRewards = await ExtraRewardPool.new(chainContracts.system.booster,{from:deployer});
    await cvxRewards.initialize(cvx.address,{from:deployer});
    console.log("cvxIncentives: " +cvxRewards.address);

    let poolManager = await PoolManager.new(chainContracts.system.booster, cvxRewards.address, {from:deployer});
    // let poolManager = await PoolManager.new(chainContracts.system.booster, chainContracts.system.cvxIncentives, {from:deployer});
    console.log("poolManager: " +poolManager.address);
    await poolManager.setPendingOwner(multisig,{from:deployer});
    console.log("set pending owner")

    return;

    //msig
    let oldpoolManager = await PoolManager.at("0x98ECe0d8aBd1f96672a497D3053999Df172FaA8b");
    await oldpoolManager.revertControl({from:multisig,gasPrice:0});
    console.log("revert old pool manager");

    let booster = await Booster.at(chainContracts.system.booster);
    await booster.setPoolManager(poolManager.address,{from:multisig,gasPrice:0})
    console.log("set new pool manager");
    await booster.poolManager().then(a=>console.log("booster.poolManager() -> " +a))

    // await poolManager.revertControl({from:deployer});
    // await booster.poolManager().then(a=>console.log("booster.poolManager() -> " +a))
    // await booster.setPoolManager(poolManager.address,{from:deployer,gasPrice:0})
    // await booster.poolManager().then(a=>console.log("booster.poolManager() -> " +a))

    let boosterOwner = await BoosterOwner.at(chainContracts.system.boosterOwner);
    await boosterOwner.setRewardManager(rewardManager.address,{from:multisig,gasPrice:0});
    console.log("set new reward manager");
    await booster.rewardManager().then(a=>console.log("booster.rewardManager() -> " +a))


    let rewardFactory = await RewardFactory.at(chainContracts.system.rewardFactory);
    await rewardFactory.mainImplementation().then(a=>console.log("mainImplementation: " +a));
    await boosterOwner.setRewardImplementation(pool.address,{from:multisig,gasPrice:0})
    await rewardFactory.mainImplementation().then(a=>console.log("mainImplementation: " +a));

    return;
  });
});


