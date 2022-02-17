// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IDeposit.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IVoting.sol";
import "./interfaces/ICrvMinter.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract FraxVoterProxy {
    using SafeERC20 for IERC20;

    address public immutable crv;
    
    address public owner;
    address public operator;
    address public depositor;
    
    // mapping (address => bool) private stashPool;
    mapping (address => bool) private protectedTokens;

    constructor(address _crv){
        crv = _crv;
        owner = msg.sender;
    }

    function getName() external pure returns (string memory) {
        return "ConvexProxy";
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "!auth");
        owner = _owner;
    }

    function setOperator(address _operator) external {
        require(msg.sender == owner, "!auth");
        require(operator == address(0) || IDeposit(operator).isShutdown() == true, "needs shutdown");
        
        operator = _operator;
    }

    function setDepositor(address _depositor) external {
        require(msg.sender == owner, "!auth");

        depositor = _depositor;
    }

    function deposit(address _token, address _gauge, uint256 _amount) external returns(bool){
        require(msg.sender == operator, "!auth");
        if(protectedTokens[_token] == false){
            protectedTokens[_token] = true;
        }
        if(protectedTokens[_gauge] == false){
            protectedTokens[_gauge] = true;
        }
        // uint256 balance = IERC20(_token).balanceOf(address(this));
        if (_amount > 0) {
            IERC20(_token).approve(_gauge, _amount);
            IGauge(_gauge).deposit(_amount);
        }
        return true;
    }

    //function for rescuing tokens that are NOT lp or gauge tokens
    function withdraw(IERC20 _asset, address _to) external returns (uint256 balance) {
        require(msg.sender == operator, "!auth");

        //check protection
        if(protectedTokens[address(_asset)] == true){
            return 0;
        }

        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(_to, balance);
        return balance;
    }

    // Withdraw partial funds
    function withdraw(address _token, address _gauge, uint256 _amount) public returns(bool){
        require(msg.sender == operator, "!auth");

        IGauge(_gauge).withdraw(_amount);
        IERC20(_token).safeTransfer(msg.sender, _amount);
        return true;
    }

     function withdrawAll(address _token, address _gauge) external returns(bool){
        require(msg.sender == operator, "!auth");
        uint256 amount = balanceOfPool(_gauge);
        withdraw(_token, _gauge, amount);
        return true;
    }

    function claimCrv(address _minter, address _gauge, address _to) external returns(uint256){
        require(msg.sender == operator, "!auth");
        
        uint256 _balance = IERC20(crv).balanceOf(address(this));
        //try mint
        try ICrvMinter(_minter).mint(_gauge){
            _balance = IERC20(crv).balanceOf(address(this)) - _balance;
            //only transfer balance that was minted
            IERC20(crv).safeTransfer(_to, _balance);
        }catch{}

        return _balance;
    }

    function claimRewards(address _gauge) external returns(bool){
        require(msg.sender == operator, "!auth");
        IGauge(_gauge).claim_rewards();
        return true;
    }

    function balanceOfPool(address _gauge) public view returns (uint256) {
        return IGauge(_gauge).balanceOf(address(this));
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