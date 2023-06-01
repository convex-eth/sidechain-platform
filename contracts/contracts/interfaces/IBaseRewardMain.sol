// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IBaseRewardMain {
   function donate(uint256 _amount) external returns(bool);
}