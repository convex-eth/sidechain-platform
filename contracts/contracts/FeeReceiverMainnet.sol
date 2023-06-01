// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFeeDistro.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "./interfaces/IBoosterMainnet.sol";
import "./interfaces/IBaseRewardMain.sol";
import "./interfaces/IVlcvxStaking.sol";


/*
    Process receieved fees to send back to mainnet

    TODO: bridging process, just hold fees for now
*/
contract FeeReceiverMainNet {
    using SafeERC20 for IERC20;

    address public operator;
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant cvxCrvRewards = address(0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e);
    address public vlcvxStaking = address(0xb5BBC863BAFE5006c68613B89130812a7b586A4e);
    address public constant cvxCRV = address(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);

    event SideChainFeesDistributed(uint256 fees);

    constructor(address _operator) {
        operator = _operator;
    }


    function setOperator(address _op) external {
        require(msg.sender == operator, "!auth");
        operator = _op;
    }

    function setVlcvxStaking(address _staking) external {
        require(msg.sender == operator, "!auth");
        vlcvxStaking = _staking;
    }

    function initialize() external {
        IERC20(crv).safeApprove(cvxCrvRewards, 0);
        IERC20(crv).safeApprove(cvxCrvRewards, type(uint256).max);
    }

    function distribute() external {

        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        emit SideChainFeesDistributed(crvBal);

        uint256 _lockIncentive = IBoosterMainnet(booster).lockIncentive();
        uint256 _stakerIncentive = IBoosterMainnet(booster).stakerIncentive();
        uint256 _platformFee = IBoosterMainnet(booster).platformFee();

        uint256 totalFees = _lockIncentive + _stakerIncentive + _platformFee;

        uint256 lockAmount = crvBal * _lockIncentive / totalFees;
        uint256 stakeAmount = crvBal * _stakerIncentive / totalFees;
        crvBal -= (lockAmount + stakeAmount);

        IBaseRewardMain(cvxCrvRewards).donate(lockAmount);

        IERC20(crv).safeTransfer(vlcvxStaking, stakeAmount);

        IERC20(crv).safeTransfer(IBoosterMainnet(booster).treasury(), crvBal);
        
    }
    
}