// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';


contract DummyToken is ERC20 {

    address public operator;

    constructor(string memory _n, string memory _s)
        ERC20(_n,_s)
    {
        operator =  msg.sender;
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