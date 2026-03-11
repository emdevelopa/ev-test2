// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/AresTreasury.sol";
import "../src/core/AresTimelockExecution.sol";
import "../src/modules/AresProposalManager.sol";
import "../src/modules/AresAuthorization.sol";
import "../src/modules/AresRewards.sol";

contract Deploy is Script {
    // ── Configuration ────────────────────────────────────────────────────────
    // Set these before deploying.
    address constant GOVERNANCE_TOKEN   = address(0);   // e.g. your ERC20Votes token
    address constant REWARD_TOKEN       = address(0);   // token distributed to contributors
    address constant AUTHORIZER         = address(0);   // multisig or guardian key

    uint256 constant TIMELOCK_DELAY     = 2 days;
    uint256 constant PROPOSAL_THRESHOLD = 100_000 ether;
    uint256 constant MAX_DRAIN_PER_EPOCH = 1_000 ether;
    uint256 constant EPOCH_DURATION     = 7 days;
    // ─────────────────────────────────────────────────────────────────────────

    function run() external {
        require(GOVERNANCE_TOKEN != address(0), "Set GOVERNANCE_TOKEN");
        require(REWARD_TOKEN     != address(0), "Set REWARD_TOKEN");
        require(AUTHORIZER       != address(0), "Set AUTHORIZER");

        vm.startBroadcast();

        // 1. Pre-compute the Authorization address so the Timelock can reference it
        //    as an immutable at construction time.
        uint64 nonce = vm.getNonce(msg.sender);
        address futureAuthAddr = vm.computeCreateAddress(msg.sender, nonce + 3);

        // 2. Timelock — only the authorization module can queue proposals
        AresTimelockExecution timelock = new AresTimelockExecution(
            TIMELOCK_DELAY,
            futureAuthAddr
        );

        // 3. Proposal Manager — gates who can propose
        AresProposalManager proposalManager = new AresProposalManager(
            GOVERNANCE_TOKEN,
            PROPOSAL_THRESHOLD
        );

        // 4. Treasury — only the timelock can move funds
        AresTreasury treasury = new AresTreasury(
            address(timelock),
            MAX_DRAIN_PER_EPOCH,
            EPOCH_DURATION
        );

        // 5. Authorization — bridges proposals into the timelock queue
        AresAuthorization authorization = new AresAuthorization(
            address(timelock),
            address(proposalManager),
            AUTHORIZER
        );

        require(address(authorization) == futureAuthAddr, "Address mismatch");

        // 6. Rewards — Merkle-based contributor distribution
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
