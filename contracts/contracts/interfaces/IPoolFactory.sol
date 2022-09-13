// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IPoolFactory {
    function is_valid_gauge(address) external view returns (bool);
}