# FlowIntents Solver SDK

TypeScript SDK for building solvers on the [FlowIntents](https://flowintents.xyz) protocol.

Solvers are agents that compete to fill user intents (yield, swap, bridge-yield) on Flow blockchain.
This SDK handles all the Cadence script/transaction encoding and EVM ABI encoding — you only write strategy logic.

## Installation

```bash
npm install
```

Dependencies: `@onflow/fcl`, `@onflow/types`, `viem`, `elliptic`, `sha3`

## Quick start

```typescript
import { FlowIntentsClient, TOKENS } from '@flowintents/solver-sdk'

const client = new FlowIntentsClient({
  flowAddress: '0xYourCadenceAddress',
  flowPrivateKey: 'yourHexPrivateKey',    // no 0x prefix
  // All other fields default to mainnet
})

// Read open intents (no key needed)
const intents = await client.getOpenIntents()

// Submit a yield bid
const encodedBatch = client.encodeANKRStakeStrategy(1.0, '0xYourEVMAddress')
const txId = await client.submitBid({
  intentID: 42,
  offeredAPY: 12.0,
  maxGasBid: 0.01,
  strategy: 'Ankr stakeCerts — 12% APY',
  encodedBatch,
})

// Execute a won intent
await client.executeIntent(42)
```

## Contract addresses (mainnet defaults)

| Contract | Address |
|---|---|
| IntentMarketplaceV0_3 (Cadence) | `0xc65395858a38d8ff` |
| FlowIntentsComposerV4 (EVM) | `0x5cc14D3509639a819f4e8f796128Fcc1C9576D95` |
| EVMBidRelay (EVM) | `0x0f58eA537424C261FB55B45B77e5a25823077E05` |

All overridable via `FlowIntentsConfig`.

## Known tokens (Flow EVM mainnet, chainId 747)

```typescript
import { TOKENS } from '@flowintents/solver-sdk'

TOKENS.WFLOW            // 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
TOKENS.stgUSDC          // 0xF1815bd50389c46847f0Bda824eC8da914045D14
TOKENS.ankrFLOW         // 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb  (bond — paused)
TOKENS.ANKR_CERT_TOKEN  // 0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A  (aFLOWEVMb — active)
TOKENS.PUNCH_ROUTER     // 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d
TOKENS.ANKR_STAKING_POOL // 0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a
```

## API reference

### `FlowIntentsClient`

#### Constructor

```typescript
new FlowIntentsClient(config?: FlowIntentsConfig)
```

`FlowIntentsConfig` fields (all optional, default to mainnet):
- `cadenceAddress` — Cadence deployer address
- `composerV4` — FlowIntentsComposerV4 EVM address
- `evmBidRelay` — EVMBidRelay EVM address
- `flowEVMRpc` — Flow EVM JSON-RPC endpoint
- `flowAccessNode` — Flow Cadence REST access node
- `flowPrivateKey` — Solver's Cadence private key (hex, no 0x)
- `flowAddress` — Solver's Cadence account address
- `keyIndex` — Key index for signing (default 0)

#### Read methods (no key required)

```typescript
// All open intents
await client.getOpenIntents(): Promise<Intent[]>

// Single intent by ID
await client.getIntent(id: number): Promise<Intent>

// Winning bid for an intent (null if not selected yet)
await client.getWinningBid(intentID: number): Promise<Bid | null>
```

#### Solver actions (require `flowPrivateKey` + `flowAddress`)

```typescript
// Submit a bid
await client.submitBid(params: BidParams): Promise<string>  // returns tx hash

// Execute a won intent (solver must be the winning bidder)
await client.executeIntent(intentID: number, recipientEVMAddress?: string): Promise<string>
```

#### Strategy encoding (pure functions, no chain calls)

```typescript
// Wrap FLOW to WFLOW
client.encodeWrapFlowStrategy(amountFlow: number, recipient: string): string

// Wrap FLOW, swap portion via PunchSwap, keep rest as WFLOW
client.encodeWrapAndSwapStrategy(
  amountFlow: number,    // total FLOW to wrap
  swapAmount: number,    // WFLOW to swap
  outputToken: string,   // e.g. TOKENS.stgUSDC
  recipient: string,
  minAmountOut: number   // in output token smallest units
): string

// Stake FLOW via Ankr FlowStakingPool (receives aFLOWEVMb)
client.encodeANKRStakeStrategy(amountFlow: number, recipient: string): string
```

### Standalone functions

All strategy encoders and chain-read functions are also exported standalone:

```typescript
import {
  getOpenIntents, getIntent,
  getBid, getWinningBid, submitBid,
  encodeWrapFlowStrategy, encodeWrapAndSwapStrategy, encodeANKRStakeStrategy,
  encodeCustomStrategy, flowToAtto, PROTOCOL,
} from '@flowintents/solver-sdk'
```

## Intent lifecycle

```
Open → BidSelected → Active → Completed
                  → Cancelled
                  → Expired
```

1. Users create intents with a gas escrow deposit
2. Solvers call `submitBid()` during the Open window
3. The intent owner (or system) calls `selectWinner()` on BidManagerV0_3
4. The winning solver calls `executeIntent()` — receives the full gas escrow
5. ComposerV4 runs the encoded strategy batch and sweeps output tokens to the recipient

## Examples

Run the included examples with a registered solver account:

```bash
FLOW_ADDRESS=0xYourAddress FLOW_PRIVATE_KEY=<hex> npx ts-node examples/swap-solver.ts
FLOW_ADDRESS=0xYourAddress FLOW_PRIVATE_KEY=<hex> npx ts-node examples/yield-solver.ts
```

**Note:** The solver account must be registered in `SolverRegistryV0_1` (Cadence) before submitting bids.

## Strategy batch format

The `encodedBatch` is ABI-encoded `StrategyStep[]`:

```solidity
struct StrategyStep {
  uint8   protocol;   // 0=MORE, 1=STARGATE, 2=LAYERZERO, 3=WFLOW_WRAP, 4=CUSTOM, 5=ANKR_STAKE
  address target;
  bytes   callData;
  uint256 value;      // attoFLOW (1 FLOW = 1e18)
}
```

Use `encodeCustomStrategy()` to build arbitrary batches from raw step descriptors.

## Build

```bash
npm run build       # compile TypeScript
npm test            # unit tests
npx tsc --noEmit    # type check only
```
