# ARES Protocol

ARES is a treasury management system built for autonomous protocols that manage large pools of on-chain capital. The core premise is simple: never trust a single control point, always delay execution, and make everything auditable.

It was designed after studying a series of real ecosystem failures — governance takeovers, flash-loan manipulation, Merkle fraud, reentrancy through timelocks, and multisig griefing. Each module targets one of these failure modes directly.

## What it does

- Accepts proposals from credentialed governance participants
- Requires off-chain cryptographic sign-off before proposals can proceed
- Delays every execution so that bad actors cannot drain funds in a single block
- Distributes contributor rewards using Merkle proofs (scales to thousands of recipients with no extra gas)
- Enforces a hard per-epoch drain cap on the treasury to prevent catastrophic governance attacks

## Project Structure

```
src/
  core/
    AresTreasury.sol          - Holds funds, enforces drain cap, executes calls
    AresTimelockExecution.sol - Queues and time-delays all proposals

  modules/
    AresProposalManager.sol   - Handles proposal creation and commit phase
    AresAuthorization.sol     - EIP-712 signature verification and nonce management
    AresRewards.sol           - Merkle-based contributor reward claiming

  interfaces/
    IAresTreasury.sol
    IAresTimelock.sol
    IAresProposalManager.sol

  libraries/
    SignatureValidator.sol    - Reusable EIP-712 domain + signer recovery logic

test/
  AresProtocol.t.sol          - Functional tests and exploit simulation tests
  MockToken.sol               - Testing helper

script/
  Deploy.s.sol                - Deployment script
```

## Build and Test

```bash
forge build
forge test -v
```

## Deployment

```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — System design, module breakdown, trust model
- [SECURITY.md](./SECURITY.md) — Attack surfaces and how each is mitigated
