// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFeeDistro.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


/*
    Process receieved fees to send back to mainnet

    TODO: briding process, just hold fees for now
*/
contract FeeDeposit is IFeeDistro{
    using SafeERC20 for IERC20;

    address public operator;

    event WithdrawTo(address indexed user, uint256 amount);

    constructor(address _operator) {
        operator = _operator;
    }

    function setOperator(address _op) external {
        require(msg.sender == operator, "!auth");
        operator = _op;
    }
    
    function onFeesClaimed() external{
        //process fees
    }

    function withdrawTo(IERC20 _asset, uint256 _amount, address _to) external {
        require(msg.sender == operator, "!auth");

        _asset.safeTransfer(_to, _amount);
        emit WithdrawTo(_to, _amount);
    }

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool, bytes memory) {
        require(msg.sender == operator,"!auth");

        (bool success, bytes memory result) = _to.call{value:_value}(_data);

        return (success, result);
    }

}