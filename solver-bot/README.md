# FlowIntents Solver Bot

An LLM-powered solver bot for the [FlowIntents](https://github.com/a0x/flowintents) protocol on Flow blockchain.

Uses Claude (`claude-haiku-4-5-20251001`) with tool use to:
1. Poll FlowIntents mainnet for open intents every 30 seconds
2. For each intent, reason about the best strategy using live protocol data
3. Submit competitive bids on-chain via the Flow CLI

## Architecture

```
solver-bot/
  src/
    index.ts    — main polling loop + Claude agentic loop
    tools.ts    — tool definitions + implementations (PunchSwap, Ankr, MORE Finance)
    chain.ts    — read intents from Flow mainnet via REST HTTP API
    submit.ts   — submit bids via Flow CLI subprocess
    config.ts   — all EVM/Cadence addresses and bot settings
  .env.example
  package.json
  tsconfig.json
```

## Setup

```bash
cp .env.example .env
# Edit .env — add your ANTHROPIC_API_KEY
npm install
npm run build
```

## Running

Dry-run mode (default — logs everything, submits nothing):
```bash
DRY_RUN=true node dist/index.js
```

Live mode (actually submits bids on-chain):
```bash
DRY_RUN=false node dist/index.js
```

TypeScript type check:
```bash
npx tsc --noEmit
```

## Tools Claude can use

| Tool | Description |
|------|-------------|
| `get_punchswap_quote` | Live quote from PunchSwap router via `getAmountsOut()` |
| `get_ankr_apy` | Current Ankr liquid staking APY (~4.2%) |
| `get_more_finance_apy` | Current MORE Finance WFLOW lending APY (~3.8%) |
| `encode_swap_strategy` | ABI-encode a 3-step FLOW→WFLOW→token swap batch |
| `encode_yield_strategy` | ABI-encode a yield batch (MORE deposit or Ankr stake) |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | (required) | Claude API key |
| `DRY_RUN` | `true` | Set to `false` to submit real transactions |
| `FLOW_NETWORK` | `mainnet` | Flow network for CLI |
| `SOLVER_CADENCE_ADDRESS` | `0xc65395858a38d8ff` | Your solver's Cadence address |
| `POLL_INTERVAL_MS` | `30000` | How often to poll (ms) |

## Intent types supported

- **Yield**: Compares Ankr (~4.2% APY) vs MORE Finance (~3.8% APY), picks best
- **Swap**: Gets PunchSwap quote for FLOW→stgUSDC (or other token), applies 5% slippage
- **BridgeYield**: Treated as Yield for now

## Protocol addresses (Flow EVM mainnet, chainId 747)

| Protocol | Address |
|----------|---------|
| WFLOW | `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` |
| stgUSDC | `0xF1815bd50389c46847f0Bda824eC8da914045D14` |
| PunchSwap Router | `0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d` |
| MORE Finance Pool | `0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d` |
| Ankr StakingPool | `0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a` |

## Sample output

```
══════════════════════════════════════════════════════════
  FlowIntents Solver Bot
  Model:      claude-haiku-4-5-20251001
  Network:    mainnet
  DRY_RUN:    true
  Poll every: 30s
══════════════════════════════════════════════════════════

[2026-03-25T10:00:00.000Z] Polling for open intents...
  Found 2 open intent(s)

────────────────────────────────────────────────────────────
Intent #3
  Type:      Yield
  Principal: 1.0 FLOW
  Target APY: 3.0%
  Duration:  30d  GasEscrow: 0.01 FLOW
  Owner:     0xc65395858a38d8ff
  Side:      cadence

  [claude] Asking Claude for bid on intent #3...
  [claude] Response (iter 1): stop_reason=tool_use
  [claude] Tool call: get_ankr_apy({})
  [claude] Tool call: get_more_finance_apy({})
  [tools] Executing: get_ankr_apy
  [tools] Result: {"protocol":"Ankr","apy":4.2,"unit":"% per year"}
  [tools] Executing: get_more_finance_apy
  [tools] Result: {"protocol":"MORE Finance","apy":3.8,"unit":"% per year"}
  [claude] Response (iter 2): stop_reason=tool_use
  [claude] Tool call: encode_yield_strategy({"protocol":"ankr","amount":1,"recipient":"0x..."})
  [tools] Executing: encode_yield_strategy
  [claude] Response (iter 3): stop_reason=end_turn
  [claude] Reasoning: Ankr offers 4.2% APY vs MORE's 3.8%...
  [claude] Bid recommendation: strategy=yield-ankr

  [bot] Submitting bid:
    strategy:        yield-ankr
    offeredAPY:      4.2%
    maxGasBid:       0.01 FLOW
    reasoning:       Ankr offers superior APY (4.2%) vs MORE Finance (3.8%)...

  [submit] DRY_RUN=true — skipping actual submission
  [bot] Bid submitted successfully for intent #3
```
