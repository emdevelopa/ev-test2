# ARCHITECTURE.md — ARES Protocol

## System Overview

ARES is a treasury execution protocol split into five independent modules. The decision to split things up this way was deliberate — we wanted to make sure a bug in one part does not automatically compromise the rest. A monolithic treasury contract is a single target; this is not that.

The five modules are:

1. **AresTreasury** — holds the funds and enforces a hard cap on how much can leave per epoch  
2. **AresTimelockExecution** — every approved proposal sits in a delay queue before it can be run  
3. **AresProposalManager** — accepts proposals, checks proposer credentials, records the full tx details  
4. **AresAuthorization** — an EIP-712 signature layer that bridges the proposal into the timelock  
5. **AresRewards** — handles Merkle-based token distribution for contributors  

## Module Separation

Each module talks to the next through a clearly defined interface. Nothing in the system calls back in unexpected directions.

**AresProposalManager** does not touch funds or signatures. It just records that someone with enough governance tokens wants a specific transaction to happen. It knows nothing about how that transaction eventually runs.

**AresAuthorization** sits between the proposal layer and the timelock. Its only job is to check a valid off-chain signature and then hand the proposal over to the queue. It maintains a per-signer nonce to prevent the same signature from being used twice.

**AresTimelockExecution** is the execution choke point. Once a proposal enters the queue, it cannot exit early. The contract stores the hash of the intended transaction, so if anyone tries to swap in different calldata at execution time, it fails. Execution is also protected against reentrancy using a manual lock that is set before any external call.

**AresTreasury** receives calls only from the timelock. No one else can tell it to move money. It tracks how much has left per epoch and blocks any call that would exceed the limit, regardless of what governance voted for.

**AresRewards** is completely separate from the main execution path. It holds reward tokens, not protocol funds, and uses a claimable Merkle drop model where each recipient proves their own eligibility. The root can only be updated by the treasury (and therefore only through governance).

## Security Boundaries

The key trust boundary runs between the authorization module and the timelock. The authorization module is the only contract allowed to add items to the timelock queue. The timelock is the only contract allowed to call the treasury. These are enforced by checking `msg.sender` against stored immutables and reverting immediately if the caller is wrong.

The treasury never trusts arbitrary input on what amounts to move — it looks up what has already left this epoch and enforces the limit mechanically, regardless of who authorized the payment.

The rewards contract enforces that each leaf in the Merkle tree can only be claimed once by tracking a packed bitmap. Setting a bit is cheaper than storing a mapping per-user and accomplishes the same guarantee.

## Trust Assumptions

The system assumes:

- The EIP-712 authorizer key is kept secure. If that key is compromised, the protocol can still only submit proposals — each proposal still has to pass through the timelock delay and the epoch drain cap.  
- The governance token has enough distribution that a single actor cannot accumulate proposal power overnight. This is a social/protocol assumption not enforced cryptographically here.  
- Block timestamps are approximately accurate. The timelock delay uses `block.timestamp`, which miners can skew by about 15 seconds in either direction. The delays we use (48 hours by default) make this negligible.  
- The Merkle root provided at each distribution epoch is computed honestly off-chain. The root update goes through governance execution, so a bad root requires a governance attack plus a timelock wait.

## Protocol Lifecycle Summary

1. A governance participant with enough token weight submits a proposal to AresProposalManager.  
2. The designated authorizer reviews it and signs an EIP-712 message approving the specific proposal ID.  
3. That signature is submitted on-chain to AresAuthorization, which verifies it and sends the proposal into the timelock queue.  
4. After the delay expires, anyone may submit the execution call with the original tx details.  
5. The timelock verifies the hash matches what was queued, then calls the treasury.  
6. The treasury checks the epoch drain limit and executes the call if it passes.  
7. At any point before execution, the authorizer can cancel the proposal.
