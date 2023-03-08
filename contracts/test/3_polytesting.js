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


const BoosterOwner = artifacts.require("BoosterOwner");
const BoosterPlaceholder = artifacts.require("BoosterPlaceholder");
const VoterProxyOwner = artifacts.require("VoterProxyOwner");


// const unlockAccount = async (address) => {
//   return new Promise((resolve, reject) => {
//     web3.currentProvider.send(
//       {
//         jsonrpc: "2.0",
//         method: "evm_unlockUnknownAccount",
//         params: [address],
//         id: new Date().getTime(),
//       },
//       (err, result) => {
//         if (err) {
//           return reject(err);
//         }
//         return resolve(result);
//       }
//     );
//   });
// };

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

contract("Deploy System and test staking/rewards", async accounts => {
  it("should deploy contracts and test various functions", async () => {

    let chainContracts = getChainContracts();
    let crv = await IERC20.at(chainContracts.curve.crv);
    let cvx = await IERC20.at(chainContracts.system.cvx);
    let deployer = chainContracts.system.deployer;
    let multisig = chainContracts.system.multisig;
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

    
    await unlockAccount(deployer);
    await unlockAccount(multisig);

    //send deployer eth
    // await web3.eth.sendTransaction({from:userA, to:deployer, value:web3.utils.toWei("10.0", "ether") });
    // console.log("sent eth to deployer");

    console.log("\n\n >>>> deploy pools >>>>")

   var usingproxy = await VoterProxy.at(chainContracts.system.voteProxy);
   await usingproxy.owner().then(a=>console.log("current proxy owner: " +a))
   await usingproxy.setPendingOwner(multisig,{from:deployer});
   await usingproxy.pendingOwner().then(a=>console.log("current proxy pending owner: " +a))
   await usingproxy.acceptPendingOwner({from:multisig,gasPrice:0})
   await usingproxy.owner().then(a=>console.log("new proxy owner: " +a))

    // return;
    var booster = await Booster.at(chainContracts.system.booster);
    var poolManager = await PoolManager.at(chainContracts.system.poolManager);
    

    let curvelp = await IERC20.at("0xa73edcf18421b56d9af1ce08a34e102e23b2c4b6");
    let lpHolder = "0x40371aad2a24ed841316ef30938881440fd4426c";
    await unlockAccount(lpHolder);
    await curvelp.transfer(userA,web3.utils.toWei("100.0", "ether"),{from:lpHolder,gasPrice:0});
    console.log("lp tokens transfered polygon-CRV+crvUSDBTCETH");

    console.log("\n\n --- deployed ----")

    console.log("\n\n >>>> staking >>>>")

    //tricrypto
    let gauge = await IGauge.at("0x40371aad2a24ed841316ef30938881440fd4426c");
    
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);

    var usePid = 8;
    var poolInfo = await booster.poolInfo(usePid);
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


    console.log("\n\n >>>> simulate staking >>>>");
    let poolUtil = await PoolUtilities.at(chainContracts.system.poolUtilities);
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))
    await poolUtil.gaugeRewardRates(0,0).then(a=>console.log("gaugeRewardRates: " +JSON.stringify(a)));

    var lpbalance = await curvelp.balanceOf(userA);
    console.log("lp balance: " +lpbalance);

    await curvelp.approve(booster.address,web3.utils.toWei("1000000.0", "ether"), {from:userA} );
    console.log("approved lp to booster");

    console.log("deposit into pid " +usePid );
    var tx = await booster.deposit(usePid, web3.utils.toWei("10", "ether"), {from:userA});
    // var tx = await booster.depositAll(usePid, {from:userA});
    console.log("deposit and staked in booster: " +tx.receipt.gasUsed);

    await rpool.balanceOf(userA).then(a=>console.log("balance in rewards: " +a))
    await rpool.totalSupply().then(a=>console.log("rewards totalSupply: " +a));
    await gauge.totalSupply().then(a=>console.log("gauge total supply: " +a))
    await gauge.balanceOf(usingproxy.address).then(a=>console.log("gauge balanceOf convex: " +a))
    await gauge.working_balances(usingproxy.address).then(a=>console.log("gauge working_balances convex: " +a))
    await gauge.working_supply().then(a=>console.log("gauge working_supply: " +a))


    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))

    //claim for other
    await rpool.methods['getReward(address)'](userA, {from:userB});
    console.log("claimed 1 (user b claims for a)");
    
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))
    await cvx.balanceOf(userA).then(a=>console.log("cvx on wallet A: " +a))
    
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
    await cvx.balanceOf(userA).then(a=>console.log("cvx on wallet A: " +a))
    await crv.balanceOf(booster.address).then(a=>console.log("crv on booster: " +a))


    let feedeposit = await FeeDeposit.at(chainContracts.system.feeDeposit);
    await crv.balanceOf(feedeposit.address).then(a=>console.log("crv on fee deposit: " +a))

    

    console.log("\n\n >>> withdraw >>>");


    await rpool.balanceOf(userA).then(a=>console.log("balance A in rewards: " +a))
    await rpool.withdrawAll(true,{from:userA});
    console.log("withdrawn");
    await rpool.balanceOf(userA).then(a=>console.log("balance in rewardsof: " +a))
    await rpool.totalSupply().then(a=>console.log("rewards totalSupply: " +a));
    await curvelp.balanceOf(userA).then(a=>console.log("curve lp balance: " +a))

    console.log("\n\n --- withdraw complete ----");


    return;
  });
});


