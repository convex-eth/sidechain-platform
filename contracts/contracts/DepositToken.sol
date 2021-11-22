// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';


contract DepositToken is ERC20 {

    address public immutable operator;
    string internal _tokenname;
    string internal _tokensymbol;

    constructor(address _operator)
        ERC20(
            "ConvexDepositToken",
            "cvxDT"
        ){
        operator = _operator;
    }

    function initialize(address _lptoken) external {
        _tokenname = string(abi.encodePacked(ERC20(_lptoken).name()," Convex Deposit"));
        _tokensymbol = string(abi.encodePacked("cvx", ERC20(_lptoken).symbol()));
    }

    function name() public view override returns (string memory) {
        return _tokenname;
    }

    function symbol() public view override returns (string memory) {
        return _tokensymbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    function mint(address _to, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        
        _burn(_from, _amount);
    }

}