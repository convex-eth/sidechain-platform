// const { BN, constants, expectEvent, expectRevert, time } = require('openzeppelin-test-helpers');
const { BN, time } = require('openzeppelin-test-helpers');
var jsonfile = require('jsonfile');
var contractList = jsonfile.readFileSync('./contracts.json');

const FeeReceiver = artifacts.require("FeeReceiverMainNet");

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

  if(NETWORK == "debug"){
    contracts = contractList.arbitrum;
  }

  console.log("using crv: " +contracts.curve.crv);
  return contracts;
}


contract("Deploy Fee Receiver Mainnet", async accounts => {
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

    //let chainContracts = getChainContracts();
    let crv = await IERC20.at("0xD533a949740bb3306d119CC777fa900bA034cd52");

    //Deploy new Fee Deposit Contract
    var newFeeReceiver = await FeeReceiver.new(deployer, {from:userA});
    console.log('Fee Receiver deployed at: ' + newFeeReceiver.address);

    //set approvals
    await newFeeReceiver.initialize();
    var checkAllowance = await crv.allowance(newFeeReceiver.address, "0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e");
    console.log('CRV Allowance: ' + checkAllowance);

    //Steal some crv
    var poorSlob = "0xB900EF131301B307dB5eFcbed9DBb50A3e209B2e";
    await unlockAccount(poorSlob);
    var poorBalance = await crv.balanceOf(poorSlob);
    console.log("poor slob crv balance: " + poorBalance);
    await crv.transfer(newFeeReceiver.address,web3.utils.toWei("100000.0", "ether"),{from:poorSlob,gasPrice:0});

    //Test distribute
    var feeBalance = await crv.balanceOf(newFeeReceiver.address);
    console.log('Fee Receiver before balance: ' + feeBalance);
    var cvxCRVBal = await crv.balanceOf("0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e");
    console.log('cvxCRV before Balance: ' + cvxCRVBal);
    var vlcvxBal = await crv.balanceOf("0xb5BBC863BAFE5006c68613B89130812a7b586A4e");
    console.log('vlcvx before balance: ' + vlcvxBal);
    var treasuryBalance = await crv.balanceOf("0x1389388d01708118b497f59521f6943Be2541bb7");
    console.log('Treasury before Balance: ' + treasuryBalance);
    await newFeeReceiver.distribute();
    var feeAfterBalance = await crv.balanceOf(newFeeReceiver.address);
    console.log('Fee Receiver after balance: ' + feeAfterBalance);
    var cvxCRVAfterBal = await crv.balanceOf("0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e");
    console.log('cvxCRV afer Balance: ' + cvxCRVAfterBal);
    var vlcvxAfterBal = await crv.balanceOf("0xb5BBC863BAFE5006c68613B89130812a7b586A4e");
    console.log('vlcvx afer balance: ' + vlcvxAfterBal);
    var treasuryAfterBalance = await crv.balanceOf("0x1389388d01708118b497f59521f6943Be2541bb7");
    console.log('Treasury after Balance: ' + treasuryAfterBalance);

    return;
  });
});


