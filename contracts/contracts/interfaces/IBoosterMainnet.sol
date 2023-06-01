// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IBoosterMainnet {
   function stakerRewards() external view returns(address);
   function lockRewards() external view returns(address);
   function treasury() external view returns(address);
   function lockIncentive() external view returns(uint256);
   function stakerIncentive() external view returns(uint256);
   function platformFee() external view returns(uint256);
}