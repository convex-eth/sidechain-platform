// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IOwner {
    function setPendingOwner(address _powner) external;
    function acceptPendingOwner() external;
    function owner() external returns(address);
    function pendingOwner() external returns(address);
}