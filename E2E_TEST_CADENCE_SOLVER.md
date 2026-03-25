# FlowIntents — E2E Tests: Cadence Solver

Tested on Flow mainnet. Account: `0xc65395858a38d8ff`

---

## Prerequisites (one-time setup)

### 1. Configure SolverRegistryV0_1 EVM addresses
```bash
flow transactions send cadence/transactions/admin/setSolverRegistryEVMAddresses.cdc \
  --args-json '[
    {"type":"String","value":"0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223"},
    {"type":"String","value":"0x1b0e6033039dC458fbBdf52E1B0346aEEb94d112"}
  ]' \
  --signer mainnet-account --network mainnet
```

### 2. Register as solver (requires ERC-8004 tokenId)
The deployer EVM key (`0xA0cD6ffcb6577BcF654efeB5e8C3F4DB89FBcda3`) has tokenId=1.

```bash
flow transactions send /tmp/register_solver_v0_1.cdc \
  --args-json '[
    {"type":"String","value":"0xA0cD6ffcb6577BcF654efeB5e8C3F4DB89FBcda3"},
    {"type":"UInt256","value":"1"}
  ]' \
  --signer mainnet-account --network mainnet
```

`/tmp/register_solver_v0_1.cdc` content:
```cadence
import EVM from "EVM"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

transaction(evmAddress: String, tokenId: UInt256) {
    let coa: &EVM.CadenceOwnedAccount
    let signerAddress: Address
    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.signerAddress = signer.address
        self.coa = signer.storage
            .borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("No COA")
    }
    execute {
        SolverRegistryV0_1.registerSolverWithAddress(
            coa: self.coa,
            cadenceAddress: self.signerAddress,
            evmAddress: evmAddress,
            tokenId: tokenId
        )
    }
}
```

### 3. Generate WFLOW encodedBatch
```bash
cd evm && forge script script/BuildWFLOWStrategy.s.sol:BuildWFLOWStrategy -vvv
# Copy the encodedBatch hex output
```

Convert to Cadence [UInt8] array:
```bash
python3 -c "
hex_batch = '<paste hex without 0x>'
bytes_list = [int(hex_batch[i:i+2],16) for i in range(0,len(hex_batch),2)]
print('[' + ','.join(['{\"type\":\"UInt8\",\"value\":\"'+str(b)+'\"}' for b in bytes_list]) + ']')
" > /tmp/wflow_batch_uint8.json
```

> **Note**: The batch is built for 1 FLOW exactly. For different amounts, rebuild with the correct `value` in `BuildWFLOWStrategy.s.sol`.

---

## Test A — Cadence YIELD Intent (WFLOW Wrap via bridge)

**Status: VERIFIED on mainnet** ✓
**Execution tx**: `244fb6cf...`
**Intent ID**: 0 on IntentMarketplaceV0_3

User creates a YIELD intent (targetAPY = 5%). Solver proposes a WFLOW wrap strategy.
The executor bridges FLOW from Cadence → EVM via COA, then calls ComposerV4 to run the batch.

### Step 1 — Get current block height (for expiry)
```bash
flow blocks get latest --network mainnet
# Add 100000 to current block height for expiryBlock
```

### Step 2 — Create YIELD intent
```bash
flow transactions send cadence/transactions/createIntentV0_3.cdc \
  --args-json '[
    {"type":"UFix64","value":"1.0"},
    {"type":"UFix64","value":"0.05"},
    {"type":"UInt64","value":"7"},
    {"type":"UInt64","value":"<currentBlock + 100000>"},
    {"type":"UFix64","value":"0.01"}
  ]' \
  --signer mainnet-account --network mainnet
```
**Output**: Note the `id` in `IntentMarketplaceV0_3.IntentCreated` event.

### Step 3 — Submit bid (Solver, WFLOW wrap strategy)
```bash
BATCH=$(cat /tmp/wflow_batch_uint8.json)
flow transactions send cadence/transactions/submitBidV0_3.cdc \
  --args-json "[
    {\"type\":\"UInt64\",\"value\":\"<intentID>\"},
    {\"type\":\"Optional\",\"value\":{\"type\":\"UFix64\",\"value\":\"0.05\"}},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"UFix64\",\"value\":\"0.005\"},
    {\"type\":\"String\",\"value\":\"WFLOW_WRAP\"},
    {\"type\":\"Array\",\"value\":$BATCH}
  ]" \
  --signer mainnet-account --network mainnet
```

### Step 4 — Select winner
```bash
flow transactions send cadence/transactions/selectWinnerV0_3.cdc \
  --args-json '[{"type":"UInt64","value":"<intentID>"}]' \
  --signer mainnet-account --network mainnet
```

### Step 5 — Execute (Cadence → EVM bridge → WFLOW wrap)
```bash
flow transactions send cadence/transactions/executeIntentV0_3.cdc \
  --args-json '[{"type":"UInt64","value":"<intentID>"}]' \
  --signer mainnet-account --network mainnet
```

**What happens internally:**
1. `IntentExecutorV0_3.executeIntentV2()` detects `principalSide = cadence`
2. Withdraws 1 FLOW from the Cadence vault
3. `coa.deposit(from: flowVault)` — bridges FLOW to COA's EVM balance
4. `coa.call(to: ComposerV4, value: 1e18, data: executeStrategyWithFunds(encodedBatch))`
5. ComposerV4 runs the WFLOW wrap: calls `WFLOW.deposit()` with 1 FLOW
6. User has 1 WFLOW in ComposerV4, gas escrow (0.01 FLOW) paid to solver

---

## Test B — Cadence SWAP Intent (WFLOW Wrap via bridge)

**Status: VERIFIED on mainnet** ✓
**Execution tx**: `19591444a8ab662b307c63ca52d8d18ea3219119af3bbdf1814ee79490fcd28a`
**Intent ID**: 1 on IntentMarketplaceV0_3

User creates a SWAP intent (`minAmountOut` instead of `targetAPY`). Same execution path as Test A —
difference is only intent semantics: SWAP = immediate exchange, YIELD = long-term position.
Same WFLOW wrap `encodedBatch` works for both.

### Step 1 — Get current block height
```bash
flow blocks get latest --network mainnet
# Add 100000 to current block height for expiryBlock
```

### Step 2 — Create SWAP intent
```bash
flow transactions send cadence/transactions/createSwapIntentV0_3.cdc \
  --args-json '[
    {"type":"UFix64","value":"1.0"},
    {"type":"UFix64","value":"0.99"},
    {"type":"UInt64","value":"30"},
    {"type":"UInt64","value":"7"},
    {"type":"UInt64","value":"<currentBlock + 100000>"},
    {"type":"UFix64","value":"0.01"}
  ]' \
  --signer mainnet-account --network mainnet
```

Parameters:
- `amount`: 1.0 FLOW to swap
- `minAmountOut`: 0.99 (solver must deliver at least 0.99 WFLOW)
- `maxFeeBPS`: 30 (0.3% max fee)
- `durationDays`: 7
- `expiryBlock`: currentBlock + 100000
- `gasEscrowAmount`: 0.01 FLOW

**Output**: Note the `id` in `IntentMarketplaceV0_3.IntentCreated` event.

### Step 3 — Submit bid (Solver, WFLOW wrap strategy)
Same `encodedBatch` as Test A (WFLOW wrap). Solver bids with `offeredAmountOut = 1.0` (1:1 wrap).
```bash
BATCH=$(cat /tmp/wflow_batch_uint8.json)
flow transactions send cadence/transactions/submitBidV0_3.cdc \
  --args-json "[
    {\"type\":\"UInt64\",\"value\":\"<intentID>\"},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"Optional\",\"value\":{\"type\":\"UFix64\",\"value\":\"1.0\"}},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"Optional\",\"value\":null},
    {\"type\":\"UFix64\",\"value\":\"0.005\"},
    {\"type\":\"String\",\"value\":\"WFLOW_WRAP\"},
    {\"type\":\"Array\",\"value\":$BATCH}
  ]" \
  --signer mainnet-account --network mainnet
```

> Bid field order: `intentID, offeredAPY (null for swap), offeredAmountOut, tokenOut, minLiquidity, solverFee, label, encodedBatch`

### Step 4 — Select winner
```bash
flow transactions send cadence/transactions/selectWinnerV0_3.cdc \
  --args-json '[{"type":"UInt64","value":"<intentID>"}]' \
  --signer mainnet-account --network mainnet
```

### Step 5 — Execute
```bash
flow transactions send cadence/transactions/executeIntentV0_3.cdc \
  --args-json '[{"type":"UInt64","value":"<intentID>"}]' \
  --signer mainnet-account --network mainnet
```

**What happens internally:**
1. `IntentExecutorV0_3.executeIntentV2()` detects `principalSide = cadence`, `intentType = Swap`
2. Same bridge path as YIELD: withdraws FLOW, bridges via COA, calls ComposerV4
3. ComposerV4 wraps FLOW → WFLOW via `WFLOW.deposit()`
4. User has 1 WFLOW in ComposerV4, gas escrow paid to solver

---

## Contracts on Mainnet

| Contract | Type | Address |
|----------|------|---------|
| IntentMarketplaceV0_3 | Cadence | `0xc65395858a38d8ff` |
| BidManagerV0_3 | Cadence | `0xc65395858a38d8ff` |
| IntentExecutorV0_3 | Cadence | `0xc65395858a38d8ff` |
| SolverRegistryV0_1 | Cadence | `0xc65395858a38d8ff` |
| FlowIntentsComposerV4 | Flow EVM | `0xe02fE15f26A3B49cfdd8De16A1352aCFf0F880e1` |
| AgentIdentityRegistry | Flow EVM | `0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223` |
| WFLOW | Flow EVM | `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` |

---

## Issues Found During Testing

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `Expiry block must be in the future` | Passed hardcoded block 9999999 < current (146M+) | Pass `currentBlock + 100000` |
| `Solver not registered in SolverRegistryV0_1` | SolverRegistryV0_1 EVM addresses were zero (never configured post-deploy) | Call `setSolverRegistryEVMAddresses.cdc` admin tx |
| `Intent does not exist` in BidManagerV0_2 | BidManagerV0_2 reads IntentMarketplaceV0_2, intents are in V0_3 | Deploy BidManagerV0_3 (wired to V0_3) |
| `FlowIntentsComposer call failed -- EVM reverted` | `authorizedCOA` in ComposerV4 was zero (never set post-deploy) | Call `setAuthorizedCOA(coaEVMAddress)` with deployer key |
| `FlowIntentsComposer call failed -- EVM reverted` | IntentExecutorV0_3 `composerAddress` pointed to old ComposerV4 | Run `setExecutorV0_3ComposerV4.cdc` admin tx with new address |
| `FlowIntentsComposer call failed -- EVM reverted` | UFix64→attoFLOW bug: `UInt(balance * 1e9) * 10 = 10^10` (sends 0.00000001 FLOW) | Fix: `UInt(balance * 100_000_000.0) * 10_000_000_000 = 10^18` |

---

## Test Intents Log

| ID | Type | Status | Amount | Params | Create tx |
|----|------|--------|--------|--------|-----------|
| 0 | YIELD | Executed ✓ | 1 FLOW | 5% APY, 7d | `095409e4...` |
| 1 | YIELD | Executed ✓ | 0.1 FLOW | EVM-only solver (executeSwapDirect) | `ffdc7c61...` |
| 1 | SWAP | Executed ✓ | 1 FLOW | 0.99 minOut, 0.3% fee, WFLOW wrap | `53bde6b5...` / exec `19591444...` |
