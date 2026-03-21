# SDK Pending Items

Items that cannot be resolved in the SDK alone and depend on deployed contracts
or configuration from other layers of the project.

---

## 1. Cadence Contract Addresses (from cadence-core)

The inline Cadence transactions in `src/Executor.ts` use placeholder addresses
that must be replaced with actual deployed contract addresses from `cadence-core`.

### Contracts needed

| Placeholder in Executor.ts    | Contract             | cadence-core source                              |
|-------------------------------|----------------------|--------------------------------------------------|
| `0xINTENT_CONTRACT`           | IntentMarketplace    | `cadence/contracts/IntentMarketplace.cdc`        |
| `0xBID_CONTRACT`              | BidManager           | `cadence/contracts/BidManager.cdc`               |
| `0xSOLVER_CONTRACT`           | SolverRegistry       | `cadence/contracts/SolverRegistry.cdc`           |

### Known addresses (cadence-core `flow.json`)

| Network   | Account                        | Status                        |
|-----------|--------------------------------|-------------------------------|
| Emulator  | `f8d6e0586b0a20c7`             | All contracts deployed here   |
| Testnet   | `Testnet contract address here`| Not yet filled in             |
| Mainnet   | —                              | Not deployed                  |

**Action required**: After testnet/mainnet deployment, update `cadence-core/flow.json`
and replace the three `0x_CONTRACT` placeholders in `sdk/src/Executor.ts`.

---

## 2. EVM Contract Addresses (from evm-core)

`src/ERC8004Manager.ts` has two zero-address placeholders:

```
ERC8004_IDENTITY_CONTRACT    = 0x0000000000000000000000000000000000000000
ERC8004_REPUTATION_CONTRACT  = 0x0000000000000000000000000000000000000000
```

### Contracts needed

| Constant                       | Contract                    | evm-core source                              |
|--------------------------------|-----------------------------|----------------------------------------------|
| `ERC8004_IDENTITY_CONTRACT`    | AgentIdentityRegistry       | `evm/src/AgentIdentityRegistry.sol`          |
| `ERC8004_REPUTATION_CONTRACT`  | AgentReputationRegistry     | `evm/src/AgentReputationRegistry.sol`        |

Both contracts are deployed to **Flow EVM mainnet (chainId 747)** and
**Flow EVM testnet (chainId 545)** once evm-core deployment scripts are run.

**Action required**: After deployment, fill in both constants in `sdk/src/ERC8004Manager.ts`.

---

## 3. ABI Notes

The SDK uses a minimal inline ABI for both ERC-8004 contracts (via `parseAbi`).
The full interface is defined in:

- `evm/src/interfaces/IAgentIdentityRegistry.sol` (identity, minting, ownership)
- `evm/src/AgentReputationRegistry.sol` (score, multiplier, history)

Key type constraint: `registerAgent(bytes32 agentType, string metadataURI)` —
`agentType` must be `keccak256(toBytes("SOLVER"))`, not a plain string.
The SDK helper `encodeAgentType(roleString)` handles this conversion automatically.

---

## 4. FCL Scripts (future)

The inline Cadence transactions in `Executor.ts` are placeholder stubs sufficient
for testnet. For production, move them to `cadence/transactions/*.cdc` files
(already exist in cadence-core) and read from disk at startup.
