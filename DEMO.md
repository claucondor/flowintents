# FlowIntents Protocol — Demo Guide

End-to-end walkthrough for the FlowIntents MVP: dual-chain intent/solver protocol on Flow blockchain.

---

## Contract Addresses

### Flow EVM Mainnet (chainId 747)

| Contract | Address |
|---|---|
| AgentIdentityRegistry (ERC-8004) | `0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223` |
| AgentReputationRegistry | `0x1b0e6033039dC458fbBdf52E1B0346aEEb94d112` |
| AgentValidationRegistry | `0x0f23a84E46fc098EfeE77281742ef8dBcDce74b1` |
| FlowIntentsComposer | `0x2253371309477118DEfbf751A4aC99f3A65b8a7e` |
| FlowIntentsComposerV2 | `0x37c6F3A5F7C27274112eB903242cD9a82239F5B9` |
| **EVMBidRelay** | **`0x4fc88d2ed70D31303784C6963F245ee18e0d1784`** |
| WFLOW | `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` |
| MORE Protocol Pool | `0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d` |
| LayerZero EndpointV2 | `0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa` |

### Flow Cadence Mainnet

| Contract | Address |
|---|---|
| IntentMarketplaceV0_3 | `0xc65395858a38d8ff` |
| BidManagerV0_2 | `0xc65395858a38d8ff` |
| IntentExecutorV0_3 | `0xc65395858a38d8ff` |
| SolverRegistryV0_1 | `0xc65395858a38d8ff` |
| ScheduledManagerV0_3 | `0xc65395858a38d8ff` |

---

## 1. Register as a Solver

### EVM-Only Path (MetaMask, no Cadence account needed in the long run)

EVM-only solvers must register **once** in `SolverRegistryV0_1` on the Cadence side. This links their EVM address to a Cadence address so bids can be tracked. The registration can be done by a **relayer** (any Cadence account that holds a COA) on the solver's behalf.

**What the solver needs:**
1. An ERC-8004 agent NFT minted in `AgentIdentityRegistry` on Flow EVM.
2. A relayer willing to call `registerSolverWithAddress` on their behalf.

**Registration transaction (relayer runs this in Flow CLI):**

```bash
flow transactions send cadence/transactions/registerSolver.cdc \
  --args-json '[
    {"type": "Address", "value": "0xSOLVER_CADENCE_ADDRESS"},
    {"type": "String",  "value": "0xSOLVER_EVM_ADDRESS"},
    {"type": "UInt256", "value": "TOKEN_ID"}
  ]' \
  --signer relayer-account \
  --network mainnet
```

> The relayer must hold a `CadenceOwnedAccount` (COA) resource in storage to make the EVM staticCall for ERC-8004 verification.

### Cadence Path (full Cadence account)

Solvers with a Cadence account use the existing `registerSolverWithAddress` function directly via `flow transactions send`. See `cadence/transactions/` for the registration transaction.

---

## 2. Create an Intent

### From Cadence (IntentMarketplaceV0_3)

```bash
flow transactions send cadence/transactions/createIntent.cdc \
  --args-json '[
    {"type": "UInt8",   "value": "0"},
    {"type": "UFix64",  "value": "5.0"},
    {"type": "UFix64",  "value": "30.0"},
    {"type": "UFix64",  "value": "100.0"},
    {"type": "Optional", "value": null},
    {"type": "Optional", "value": null},
    {"type": "Optional", "value": null}
  ]' \
  --signer user-account \
  --network mainnet
```

Fields: `intentType=0 (Yield)`, `minAPY=5.0`, `durationDays=30`, `principalAmount=100 FLOW`, then optional `minAmountOut`, `targetChain`, `maxGasBudget`.

### From EVM (FlowIntentsComposerV2)

```bash
cast send 0x37c6F3A5F7C27274112eB903242cD9a82239F5B9 \
  "submitIntent(address,uint256,uint256,uint256,uint8)" \
  0x0000000000000000000000000000000000000000 \
  0 \
  500 \
  30 \
  0 \
  --value 1ether \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key $PRIVATE_KEY
```

Parameters: `token=address(0) (native FLOW)`, `amount=0 (ignored for native)`, `targetAPY=500 bps (5%)`, `durationDays=30`, `principalSide=0 (EVM_YIELD)`. Send 1 FLOW as value.

---

## 3. Submit a Bid

### EVM Path via EVMBidRelay (MetaMask / cast)

EVM-only solvers post bids directly to `EVMBidRelay`. A Cadence relayer periodically reads the relay and forwards bids to `BidManagerV0_2`.

```bash
# Build the encodedBatch first (see section 4 below)
ENCODED_BATCH=0x... # from BuildWFLOWStrategy or BuildMOREDepositStrategy

cast send 0x4fc88d2ed70D31303784C6963F245ee18e0d1784 \
  "submitBid(uint256,uint256,uint256,bytes)" \
  1 \
  500 \
  100000000000000000 \
  $ENCODED_BATCH \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key $PRIVATE_KEY
```

Parameters: `intentId=1`, `offeredAPY=500 bps (5%)`, `maxGasBid=0.1 FLOW (1e17 attoFLOW)`, `encodedBatch`.

**Then the relayer forwards the bid to Cadence:**

```bash
flow transactions send cadence/transactions/relayEVMBid.cdc \
  --args-json '[
    {"type": "UInt64",  "value": "1"},
    {"type": "String",  "value": "0xSOLVER_EVM_ADDRESS"},
    {"type": "UFix64",  "value": "5.0"},
    {"type": "UFix64",  "value": "0.1"},
    {"type": "String",  "value": "{\"protocol\":\"WFLOW_WRAP\",\"steps\":1}"},
    {"type": "Array",   "value": [...encodedBatch as [UInt8]...]}
  ]' \
  --signer relayer-account \
  --network mainnet
```

### Cadence Path (submitBid.cdc)

```bash
flow transactions send cadence/transactions/submitBid.cdc \
  --args-json '[
    {"type": "UInt64",  "value": "1"},
    {"type": "UFix64",  "value": "5.0"},
    {"type": "Optional","value": null},
    {"type": "Optional","value": null},
    {"type": "Optional","value": null},
    {"type": "UFix64",  "value": "0.1"},
    {"type": "String",  "value": "{\"strategy\":\"wflow_wrap\"}"},
    {"type": "Array",   "value": [...encodedBatch as [UInt8]...]}
  ]' \
  --signer solver-account \
  --network mainnet
```

---

## 4. WFLOW Wrap Intent — Full Example

This example demonstrates: user deposits 1 FLOW, solver wraps it to WFLOW via `WFLOW.deposit()`.

### Step 1: Generate the encodedBatch

```bash
cd evm
forge script script/BuildWFLOWStrategy.s.sol:BuildWFLOWStrategy -vvv
```

Example output for 1 FLOW:
```
encodedBatch:
0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000300000000000000000000000 0d3bf53dac106a0290b0483ecbc89d40fcc961f3e00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000004d0e30db000000000000000000000000000000000000000000000000000000000
```

### Step 2: User creates the intent (EVM)

```bash
cast send 0x37c6F3A5F7C27274112eB903242cD9a82239F5B9 \
  "submitIntent(address,uint256,uint256,uint256,uint8)" \
  0x0000000000000000000000000000000000000000 0 500 30 0 \
  --value 1ether \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key $USER_PRIVATE_KEY
```

### Step 3: Solver submits bid to EVMBidRelay

```bash
cast send 0x4fc88d2ed70D31303784C6963F245ee18e0d1784 \
  "submitBid(uint256,uint256,uint256,bytes)" \
  1 500 100000000000000000 \
  0x[ENCODED_BATCH_FROM_STEP_1] \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key $SOLVER_PRIVATE_KEY
```

### Step 4: Relayer forwards bid to Cadence BidManager

```bash
flow transactions send cadence/transactions/relayEVMBid.cdc \
  [args as shown in section 3] \
  --signer relayer-account \
  --network mainnet
```

### Step 5: Intent owner selects winner and executor runs the strategy

The `ScheduledManagerV0_3` on Cadence monitors open intents. Once a winner is selected, `IntentExecutorV0_3` calls `FlowIntentsComposerV2.executeStrategy()` via COA with the `encodedBatch`, which executes `WFLOW.deposit()` sending the user's FLOW to WFLOW.

---

## 5. MORE Protocol Deposit Strategy

```bash
cd evm
forge script script/BuildMOREDepositStrategy.s.sol:BuildMOREDepositStrategy -vvv
```

This produces a 2-step batch:
1. `WFLOW.approve(MORE_POOL, amount)` — approve the pool to spend WFLOW
2. `MORE_POOL.deposit(WFLOW, amount, receiver, 0)` — deposit WFLOW into MORE for yield

Use the output as `encodedBatch` in `EVMBidRelay.submitBid()` or `BidManagerV0_2.submitBid()`.

---

## Environment Setup

```bash
# Install dependencies
cd evm && forge install

# Set environment variables
cp .env.example .env
# Edit .env: set DEPLOYER_PRIVATE_KEY

# Run tests
forge test -v

# Deploy EVMBidRelay standalone
source .env
PRIVATE_KEY=$DEPLOYER_PRIVATE_KEY forge script evm/script/DeployEVMBidRelay.s.sol:DeployEVMBidRelay \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --broadcast --private-key $DEPLOYER_PRIVATE_KEY -vvv
```

---

## Architecture Summary

```
EVM Solver (MetaMask)
      |
      | submitBid()
      v
EVMBidRelay.sol  <-- permissionless EVM bid board
      |
      | Cadence relayer reads off-chain, calls relayEVMBid.cdc
      v
BidManagerV0_2 (Cadence)
      |
      | selectWinner() / ScheduledManagerV0_3
      v
IntentExecutorV0_3 (Cadence) via COA
      |
      | executeStrategy() on FlowIntentsComposerV2
      v
WFLOW.deposit() / MORE_POOL.deposit()
```
