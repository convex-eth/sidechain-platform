// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IVoterProxy {
    function setOperator(address _operator) external;
    function setDepositor(address _depositor) external;
    function setOwner(address _owner) external;
    function acceptPendingOwner() external;
    function owner() external returns(address);
    function operator() external returns(address);
    function depositor() external returns(address);
}