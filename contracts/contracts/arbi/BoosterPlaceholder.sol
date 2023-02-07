// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

//minimal placehodler contract that has isShutdown interface
contract BoosterPlaceholder{

    bool public isShutdown;

    constructor() {
        isShutdown = true;
    }
}