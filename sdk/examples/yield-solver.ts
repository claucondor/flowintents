/**
 * examples/yield-solver.ts
 *
 * Example yield solver that:
 *   1. Polls open intents every 30 seconds
 *   2. For each Yield intent, picks the best strategy (ANKR staking vs WFLOW wrap)
 *   3. Submits a bid with the encoded batch
 *   4. Logs APY offerings and strategy selection
 *
 * To run:
 *   FLOW_ADDRESS=0xYourAddress FLOW_PRIVATE_KEY=yourHexKey npx ts-node examples/yield-solver.ts
 */

import {
  FlowIntentsClient,
  encodeWrapFlowStrategy,
  encodeANKRStakeStrategy,
  type Intent,
} from '../src/index'

// ─────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────

const FLOW_ADDRESS = process.env.FLOW_ADDRESS ?? ''
const FLOW_PRIVATE_KEY = process.env.FLOW_PRIVATE_KEY ?? ''
const SOLVER_EVM_ADDRESS = process.env.SOLVER_EVM_ADDRESS ?? '0x0000000000000000000000000000000000000000'

const POLL_INTERVAL_MS = 30_000
const MAX_GAS_BID = 0.01

// ─────────────────────────────────────────────
// Strategy catalogue
// ─────────────────────────────────────────────

interface YieldStrategy {
  name: string
  apy: number
  encode: (amountFlow: number, recipient: string) => string
}

/**
 * Available yield strategies, ranked by expected APY.
 * In production, fetch live APY from on-chain sources or MCP.
 */
const YIELD_STRATEGIES: YieldStrategy[] = [
  {
    name: 'Ankr stakeCerts (aFLOWEVMb)',
    apy: 12.0, // Approximate; check AnkrStakingPool.getApr() on-chain for live rate
    encode: encodeANKRStakeStrategy,
  },
  {
    name: 'WFLOW wrap',
    apy: 3.5, // Approximate; WFLOW earns yield via underlying DeFi protocols
    encode: encodeWrapFlowStrategy,
  },
]

function pickBestStrategy(intentTargetAPY: number): YieldStrategy | null {
  // Filter to strategies that meet the intent's target APY
  const viable = YIELD_STRATEGIES.filter((s) => s.apy >= intentTargetAPY)
  if (viable.length === 0) {
    return null // No strategy meets the target — skip this intent
  }
  // Return highest APY strategy
  return viable.sort((a, b) => b.apy - a.apy)[0]
}

// ─────────────────────────────────────────────
// Bid submission
// ─────────────────────────────────────────────

async function processYieldIntent(client: FlowIntentsClient, intent: Intent): Promise<void> {
  console.log(`\n[solver] Processing Yield intent #${intent.id}`)
  console.log(`         principal:  ${intent.principalAmount} FLOW`)
  console.log(`         targetAPY:  ${intent.targetAPY}%`)
  console.log(`         duration:   ${intent.durationDays} days`)
  console.log(`         gas escrow: ${intent.gasEscrowBalance} FLOW`)

  const strategy = pickBestStrategy(intent.targetAPY)
  if (!strategy) {
    console.log(`[solver] No strategy meets targetAPY ${intent.targetAPY}% — skipping`)
    return
  }

  console.log(`[solver] Selected strategy: ${strategy.name} (${strategy.apy}% APY)`)

  const recipient = intent.recipientEVMAddress ?? SOLVER_EVM_ADDRESS
  const encodedBatch = strategy.encode(intent.principalAmount, recipient)

  const strategyDesc = `${strategy.name} | ${strategy.apy}% APY | recipient: ${recipient}`

  console.log(`[solver] Submitting bid...`)

  const txId = await client.submitBid({
    intentID: intent.id,
    offeredAPY: strategy.apy,
    offeredAmountOut: undefined,
    maxGasBid: MAX_GAS_BID,
    strategy: strategyDesc,
    encodedBatch,
  })

  console.log(`[solver] Bid submitted! Cadence tx: ${txId}`)
  console.log(`         Offered APY: ${strategy.apy}% via ${strategy.name}`)
}

// ─────────────────────────────────────────────
// Polling loop
// ─────────────────────────────────────────────

const biddedIntents = new Set<number>()

async function poll(client: FlowIntentsClient): Promise<void> {
  console.log(`\n[solver] Polling at ${new Date().toISOString()}...`)

  let intents: Intent[]
  try {
    intents = await client.getOpenIntents()
  } catch (err) {
    console.error('[solver] Failed to fetch intents:', err)
    return
  }

  const yieldIntents = intents.filter((i) => i.intentType === 'Yield')
  console.log(`[solver] ${intents.length} total open, ${yieldIntents.length} Yield intents`)

  for (const intent of yieldIntents) {
    if (biddedIntents.has(intent.id)) continue

    try {
      await processYieldIntent(client, intent)
      biddedIntents.add(intent.id)
    } catch (err) {
      console.error(`[solver] Error on intent #${intent.id}:`, err)
    }
  }
}

// ─────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────

async function main() {
  if (!FLOW_ADDRESS || !FLOW_PRIVATE_KEY) {
    console.error('ERROR: Set FLOW_ADDRESS and FLOW_PRIVATE_KEY environment variables.')
    process.exit(1)
  }

  console.log('=== FlowIntents Yield Solver ===')
  console.log(`Account:  ${FLOW_ADDRESS}`)
  console.log(`Network:  mainnet`)
  console.log(`Strategies: ANKR stakeCerts (12% APY), WFLOW wrap (3.5% APY)`)
  console.log(`Poll: every ${POLL_INTERVAL_MS / 1000}s`)
  console.log('================================\n')

  const client = new FlowIntentsClient({
    flowAddress: FLOW_ADDRESS,
    flowPrivateKey: FLOW_PRIVATE_KEY,
  })

  await poll(client)

  setInterval(() => {
    poll(client).catch((err) => console.error('[solver] Poll error:', err))
  }, POLL_INTERVAL_MS)
}

main().catch((err) => {
  console.error('Fatal error:', err)
  process.exit(1)
})
