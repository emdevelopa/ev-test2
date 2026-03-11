// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/AresTreasury.sol";
import "../src/core/AresTimelockExecution.sol";
import "../src/modules/AresProposalManager.sol";
import "../src/modules/AresAuthorization.sol";
import "../src/modules/AresRewards.sol";

contract Deploy is Script {
  
    
    address constant GOVERNANCE_TOKEN   = address(0);  
    address constant REWARD_TOKEN       = address(0);   
    address constant AUTHORIZER         = address(0);   

    uint256 constant TIMELOCK_DELAY     = 2 days;
    uint256 constant PROPOSAL_THRESHOLD = 100_000 ether;
    uint256 constant MAX_DRAIN_PER_EPOCH = 1_000 ether;
    uint256 constant EPOCH_DURATION     = 7 days;
  
    function run() external {
        require(GOVERNANCE_TOKEN != address(0), "Set GOVERNANCE_TOKEN");
        require(REWARD_TOKEN     != address(0), "Set REWARD_TOKEN");
        require(AUTHORIZER       != address(0), "Set AUTHORIZER");

        vm.startBroadcast();

      
        uint64 nonce = vm.getNonce(msg.sender);
        address futureAuthAddr = vm.computeCreateAddress(msg.sender, nonce + 3);

        
        AresTimelockExecution timelock = new AresTimelockExecution(
            TIMELOCK_DELAY,
            futureAuthAddr
        );

   
        AresProposalManager proposalManager = new AresProposalManager(
            GOVERNANCE_TOKEN,
            PROPOSAL_THRESHOLD
        );
 
        AresTreasury treasury = new AresTreasury(
            address(timelock),
            MAX_DRAIN_PER_EPOCH,
            EPOCH_DURATION
        );

       
        AresAuthorization authorization = new AresAuthorization(
            address(timelock),
            address(proposalManager),
            AUTHORIZER
        );

        require(address(authorization) == futureAuthAddr, "Address mismatch");

         
        AresRewards rewards = new AresRewards(
            REWARD_TOKEN,
            address(treasury)
        );

        vm.stopBroadcast();

        console.log("=== ARES Protocol Deployment ===");
        console.log("AresTimelockExecution:", address(timelock));
        console.log("AresProposalManager:  ", address(proposalManager));
        console.log("AresTreasury:         ", address(treasury));
        console.log("AresAuthorization:    ", address(authorization));
        console.log("AresRewards:          ", address(rewards));
    }
}
