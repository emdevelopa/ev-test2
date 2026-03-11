// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Mock token for testing
contract MockToken {
    string public constant name = "Governance Token";
    string public constant symbol = "GOV";
    uint8 public constant decimals = 18;
    
    mapping(address => uint256) public balanceOf;
    
    constructor() {
        balanceOf[msg.sender] = 1_000_000 * 10**18;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function getVotes(address account) external view returns (uint256) {
        return balanceOf[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
