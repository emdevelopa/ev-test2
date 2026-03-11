# SECURITY.md — ARES Protocol

## Overview

In this document I explain what attack types the ARES protocol was built to resist and where the real risks remain. We try to be honest about both.

---

## Attack Surfaces and Mitigations

### 1. Reentrancy

**The problem:** A malicious contract receives ETH or tokens during execution and immediately calls back into the system, before the state has been marked as completed. This is how many timelock bypasses happen in production — the caller re-enters while the proposal is still technically "Queued".

**How the protocol stops it:** `AresTimelockExecution.executeProposal` uses a manual reentrancy guard that sets a flag to `_ENTERED` before any external call and checks that flag at entry. If a malicious contract's fallback tries to call `executeProposal` again, it hits an immediate revert with `ReentrantCall()`. The state is also set to `Executed` before the external call goes out.

---

### 2. Signature Replay

**The problem:** A valid signature is captured and resubmitted — either on the same chain to authorize the same proposal twice, or on a different chain where the same contracts exist with the same addresses.

**How the protocol stops it:** Signatures follow the EIP-712 standard. The domain separator includes the chain ID and the verifying contract's address. This means the same signature cannot be used on a different chain or with a different deployment. Per-authorizer nonces are tracked on-chain — every successful authorization increments the nonce, so the same signature cannot be used again on the same chain either.

---

### 3. Signature Malleability

**The problem:** ECDSA signatures have two valid forms (`s` and `n - s`). An attacker could alter the raw bytes of a valid signature and get a different but technically valid-looking signature for the same message.

**How the protocol stops it:** We use EIP-712 structured hashing which means the protocol are ssigning over a well-defined struct, not over raw arbitrary data. We also map authorizations to proposal IDs — once a proposal has been authorized, `authorizedProposals[proposalId]` is set to `true` and any second attempt reverts immediately, regardless of what signature shape is tried.

---

### 4. Double Claim

**The problem:** A contributor claims their reward tokens once, then calls claim again before the contract updates its state.

**How the protocol stops it:** `AresRewards` uses a packed bitmap (`mapping(uint256 => uint256) claimedBitMap`) to track which Merkle leaf indices have been claimed. Before doing anything, the function checks if the bit corresponding to the given index is set. If it is, the call reverts with `AlreadyClaimed()`. The bit is set before the token transfer goes out, so there is no window for a reentrancy-style double claim.

---

### 5. Flash-Loan Governance Manipulation

**The problem:** An attacker borrows a massive amount of governance tokens within a single transaction, votes or proposes with that weight, then returns the tokens. Standard snapshot governance can often be attacked this way if the snapshot is taken at the current block.

**How the protocol stops it:** Two layers of protection. First, AresProposalManager's threshold check uses the current token balance at proposal time — any protocol using this in production should make the governance token non-flashloanable (e.g., via ERC20Votes with past-block snapshot). Second, even if a proposal gets through, it still requires the authorized off-chain signer to approve it explicitly. A flash loan cannot forge that signature. Third, the timelock delay means by the time the proposal could execute, the loan has long since been repaid and any borrowed voting power is gone.

---

### 6. Large Treasury Drain

**The problem:** Compromised governance passes a proposal to drain most or all of the treasury in a single transaction. Even with a timelock, if no one notices in time, everything gets taken.

**How the protocol stops it:** `AresTreasury` tracks how much ETH has left in the current epoch and blocks any call that would push spending past `maxDrainPerEpoch`. If governance tries to pass two large withdrawals in the same epoch, the second will revert with `DrainLimitExceeded()`. This is a hard coded circuit breaker. The drain limit and epoch duration are set at deployment and can only be updated via governance (i.e., through the full proposal + timelock cycle).

---

### 7. Unauthorized Execution / Proposal Replay

**The problem:** Someone tries to execute a proposal that was never queued, or tries to execute an already-executed proposal a second time.

**How the protocol stops it:** Every proposal in the timelock has a `ProposalState` enum that starts at `Inactive`. It can only become `Queued` through the authorization module. Once it is `Executed` or `Cancelled`, any subsequent call to `executeProposal` with the same ID hits the `InvalidState` check and reverts immediately. The transaction hash stored at queue time must also exactly match what is provided at execution time — swapping in different calldata reverts.

---

### 8. Proposal Griefing / Threshold Bypass

**The problem:** Anyone can spam proposals, clogging governance. Or a user with no tokens tries to propose something malicious.

**How this stop it:** `AresProposalManager` reads the proposer's vote balance from the governance token before storing the proposal. If the balance is below the `proposalThreshold`, it reverts with `BelowProposalThreshold()`. No token balance, no proposal.

---

## Remaining Risks

**Off-chain authorizer compromise:** If the private key of the authorized signer is leaked, an attacker can sign proposals. This is mitigated by the drain cap (they cannot take everything at once) and the timelock delay (there is a window to react and cancel queued proposals). In production, this role should be held by a multisig rather than a single key.

**Timestamp manipulation:** The timelock delay uses `block.timestamp`. Validators can shift timestamps by ~15 seconds. For delays in the range of 48 hours this is not a meaningful attack surface. If delays were in the minutes range, this would matter more.

**Merkle root compromise:** If the off-chain process that computes the rewards tree is compromised before a root update goes through governance, recipients could receive wrong amounts. Each root update still requires a governance proposal + timelock wait, so there is a window to catch fraud before it lands on chain.

**Token contract trust:** `AresRewards` calls `transfer` on the reward token. If that token's contract has a bug or a malicious upgrade, the rewards module would be affected. This is outside the protocol boundary.

---

## Protocol Specification

### Proposal Creation
Any account holding at least `proposalThreshold` governance tokens calls `AresProposalManager.propose(target, value, data)`. The full calldata is stored on-chain with the proposer's address and a timestamp. A unique incrementing proposal ID is returned.

### Approval
The designated authorizer signs an EIP-712 message containing the proposal ID and their current nonce. This signature is submitted on-chain to `AresAuthorization.authorizeProposal`. The contract recovers the signer via `ecrecover`, checks it matches the expected authorizer, increments the nonce, marks the proposal as authorized, and pushes it into the timelock queue.

### Queueing
`AresTimelockExecution.queueProposal` is called only by the authorization module. It records a hash of `(target, value, data)` and sets `executeAfter = block.timestamp + DELAY`. The proposal state moves from `Inactive` to `Queued`.

### Execution
After the delay has passed, anyone may call `AresTimelockExecution.executeProposal` with the original `(proposalId, target, value, data)`. The contract re-hashes the inputs and compares against the stored hash. If they match and the delay has passed, state is set to `Executed` and the call is forwarded to the treasury. The treasury applies the drain cap before running the actual call.

### Cancellation
The authorization module can cancel a `Queued` proposal at any time before execution by calling `AresTimelockExecution.cancelProposal`. State moves to `Cancelled`. An event is emitted so that off-chain monitors can track this. Once cancelled, the proposal cannot be requeued or executed.
