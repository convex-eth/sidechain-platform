// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IDepositToken {
   function initialize(address _lptoken) external;
   function mint(address _to, uint256 _amount) external;
   function burn(address _from, uint256 _amount) external;
   function name() external view returns (string memory);
   function symbol() external view returns (string memory);
   function decimals() external view returns (uint8);
}