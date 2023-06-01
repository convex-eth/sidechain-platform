// const { BN, constants, expectEvent, expectRevert, time } = require('openzeppelin-test-helpers');
const { BN, time } = require('openzeppelin-test-helpers');
var jsonfile = require('jsonfile');
var contractList = jsonfile.readFileSync('./contracts.json');

const FeeBridge = artifacts.require("FeeBridgeArbi");

const IERC20 = artifacts.require("IERC20");


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


contract("Deploy Fee Bridge Arbi", async accounts => {
  it("should deploy contracts", async () => {

    let deployer = "0x051C42Ee7A529410a10E5Ec11B9E9b8bA7cbb795";

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

    //Deploy new Fee Deposit Contract
    var newFeeBridge = await FeeBridge.new(deployer, deployer,{from:deployer});
    console.log('Fee Deposit deployed at: ' + newFeeBridge.address);

    //set approvals
    await newFeeBridge.initialize();
    var checkAllowance = await crv.allowance(newFeeBridge.address, "0x0caE51e1032e8461f4806e26332c030E34De3aDb");
    console.log('CRV Allowance bridge: ' + checkAllowance);
    var feeDepositAddress = await newFeeBridge.feeDeposit();
    await unlockAccount(feeDepositAddress);
    await crv.approve(newFeeBridge.address, web3.utils.toWei("1000000000000000000000000.0", "ether"), {from:feeDepositAddress,gasPrice:0});
    var checkFeeDeposit = await crv.allowance(feeDepositAddress, newFeeBridge.address);
    console.log('CRV Allowance feedeposit: ' + checkFeeDeposit);
    

    // Send CRV to new contract
    var feeBalance = await crv.balanceOf(feeDepositAddress);
    console.log('Fee Deposit Contract CRV balance(before processing): ' + feeBalance);
    var receiver = await newFeeBridge.root_receiver();
    console.log("Root Receiver: " + receiver);

    await newFeeBridge.processFees();
    var postBalance = await crv.balanceOf(feeDepositAddress);
    console.log('Fee Deposit CRV Balance post processing: ' + postBalance);

    var bridgeBalance = await crv.balanceOf(newFeeBridge.address);
    console.log('Fee Bridge Balance post processing(should be zero): ' + bridgeBalance); 

    var lastTime = await newFeeBridge.lastProcessFee();

    console.log('last process time: ' + lastTime);

    return;
  });
});


