// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IAnySwapRouter {
   function anySwapOut(address token, address to, uint amount, uint toChainID) external;
   function anySwapOutUnderlying(address token, address to, uint amount, uint toChainID) external;
}