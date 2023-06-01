// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFeeDistro.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "./interfaces/IAnySwapRouter.sol";



contract FeeBridgeArbi is IFeeDistro{
    using SafeERC20 for IERC20;

    address public operator;
    address public root_receiver;
    address public multichain_router = address(0x0caE51e1032e8461f4806e26332c030E34De3aDb);
    address public feeDeposit = address(0xE7CdD5ed586A095e395f2007449721eA2a5B878a);
    address public constant crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address public constant anyCRV = address(0x7BEB05cf5681f402E762F8569c2Fc138a2172978);
    uint256 public lastProcessFee = 0;

    event FeesSentToMain(uint256 fees);

    

    event WithdrawTo(address indexed user, uint256 amount);

    constructor(address _operator, address _receiver) {
        operator = _operator;
        root_receiver = _receiver;
    }

    function initialize() external {
        IERC20(crv).safeApprove(multichain_router, 0);
        IERC20(crv).safeApprove(multichain_router, type(uint256).max);
    }

    function setOperator(address _op) external {
        require(msg.sender == operator, "!auth");
        operator = _op;
    }

    function setReceiver(address _receiver) external {
        require(msg.sender == operator, "!auth");
        root_receiver = _receiver;
    }

    function setRouter(address _router) external {
        require(msg.sender == operator, "!auth");
        multichain_router = _router;
    }

    function setFeeDeposit(address _feeDeposit) external {
        require(msg.sender == operator, "!auth");
        feeDeposit = _feeDeposit;
    }

    
    function processFees() external{
        uint256 crvBal = IERC20(crv).balanceOf(feeDeposit);
        IERC20(crv).safeTransferFrom(feeDeposit, address(this), crvBal);
        IAnySwapRouter(multichain_router).anySwapOutUnderlying(anyCRV, root_receiver, crvBal, 1);
        lastProcessFee = block.timestamp;
        emit FeesSentToMain(crvBal);
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