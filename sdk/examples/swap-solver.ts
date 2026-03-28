/**
 * examples/swap-solver.ts
 *
 * Example swap solver that:
 *   1. Polls open intents every 30 seconds
 *   2. For each Swap intent, calculates a PunchSwap quote (mocked here)
 *   3. Submits a bid with the WrapAndSwap strategy
 *   4. Logs everything clearly
 *
 * To run:
 *   FLOW_ADDRESS=0xYourAddress FLOW_PRIVATE_KEY=yourHexKey npx ts-node examples/swap-solver.ts
 *
 * Requirements:
 *   - The solver account must be registered in SolverRegistryV0_1 (Cadence)
 *   - The solver must have a COA at /storage/evm (needed for executeIntent)
 */

import {
  FlowIntentsClient,
  encodeWrapAndSwapStrategy,
  TOKENS,
  type Intent,
} from '../src/index'

// ─────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────

const FLOW_ADDRESS = process.env.FLOW_ADDRESS ?? ''
const FLOW_PRIVATE_KEY = process.env.FLOW_PRIVATE_KEY ?? ''
const SOLVER_EVM_ADDRESS = process.env.SOLVER_EVM_ADDRESS ?? '0x0000000000000000000000000000000000000000'

/** How often to poll for new intents (ms). */
const POLL_INTERVAL_MS = 30_000

/** Maximum FLOW amount this solver is willing to wrap per intent. */
const MAX_FLOW_PER_INTENT = 10.0

/** Gas bid in FLOW (solver requests this from the user's escrow). */
const MAX_GAS_BID = 0.01

// ─────────────────────────────────────────────
// PunchSwap quote (mock)
//
// In production, query the PunchSwap V2 router's getAmountsOut() via viem:
//   const [amountIn, amountOut] = await publicClient.readContract({
//     address: TOKENS.PUNCH_ROUTER,
//     abi: uniV2RouterAbi,
//     functionName: 'getAmountsOut',
//     args: [swapAmountAtto, [TOKENS.WFLOW, TOKENS.stgUSDC]],
//   })
// ─────────────────────────────────────────────

interface SwapQuote {
  /** Expected output amount in token smallest units. */
  expectedOut: bigint
  /** 95% of expectedOut — used as minAmountOut for slippage protection. */
  minAmountOut: bigint
  /** Human-readable description. */
  description: string
}

function getPunchSwapQuote(amountFlowToSwap: number, _outputToken: string): SwapQuote {
  // MOCK: observed rate ~3138 stgUSDC (6 decimals) per 0.1 WFLOW
  // Real implementation: call router.getAmountsOut(amountIn, [WFLOW, tokenOut])
  const ratePerFlow = 31380n // stgUSDC units per 1.0 WFLOW (6 decimals)
  const inputAtto = BigInt(Math.round(amountFlowToSwap * 1e6)) // scale to 6dp precision
  const expectedOut = (ratePerFlow * inputAtto) / 1_000_000n
  const minAmountOut = (expectedOut * 95n) / 100n // 5% slippage tolerance

  return {
    expectedOut,
    minAmountOut,
    description: `PunchSwap WFLOW→stgUSDC: ~${Number(expectedOut)} stgUSDC units (mock quote)`,
  }
}

// ─────────────────────────────────────────────
// Bid submission
// ─────────────────────────────────────────────

async function processSwapIntent(client: FlowIntentsClient, intent: Intent): Promise<void> {
  console.log(`\n[solver] Processing Swap intent #${intent.id}`)
  console.log(`         principal:    ${intent.principalAmount} FLOW`)
  console.log(`         minAmountOut: ${intent.minAmountOut ?? 'unset'}`)
  console.log(`         maxFeeBPS:    ${intent.maxFeeBPS ?? 'unset'}`)
  console.log(`         recipient:    ${intent.recipientEVMAddress ?? '(default COA)'}`)

  // How much FLOW to wrap — use all of the principal (up to our max)
  const amountFlow = Math.min(intent.principalAmount, MAX_FLOW_PER_INTENT)
  // Swap half, keep half as WFLOW (simple strategy — adjust per your alpha)
  const swapAmount = amountFlow / 2

  // Get a quote for the swap portion
  const quote = getPunchSwapQuote(swapAmount, TOKENS.stgUSDC)
  console.log(`         quote:        ${quote.description}`)

  // Check that our offered amount meets the intent's minimum
  if (intent.minAmountOut != null && quote.expectedOut < BigInt(Math.round(intent.minAmountOut))) {
    console.log(`[solver] Quote ${quote.expectedOut} below intent minAmountOut ${intent.minAmountOut} — skipping`)
    return
  }

  // Determine recipient for the swap output
  const recipient = intent.recipientEVMAddress ?? SOLVER_EVM_ADDRESS

  // Encode the 3-step WrapAndSwap strategy
  const encodedBatch = encodeWrapAndSwapStrategy(
    amountFlow,        // total FLOW to wrap
    swapAmount,        // WFLOW amount to swap
    TOKENS.stgUSDC,    // output token
    recipient,         // receives stgUSDC
    quote.minAmountOut,
  )

  const strategyDesc = [
    `WrapAndSwap: ${amountFlow} FLOW → ${swapAmount} WFLOW swapped to stgUSDC + ${amountFlow - swapAmount} WFLOW kept`,
    `Recipient: ${recipient}`,
    `minAmountOut: ${quote.minAmountOut} stgUSDC units`,
    `via PunchSwap (mock quote)`,
  ].join(' | ')

  console.log(`[solver] Submitting bid...`)
  console.log(`         strategy: ${strategyDesc.slice(0, 80)}...`)

  const txId = await client.submitBid({
    intentID: intent.id,
    offeredAPY: undefined,
    offeredAmountOut: Number(quote.expectedOut),  // UFix64: offered stgUSDC units as float
    maxGasBid: MAX_GAS_BID,
    strategy: strategyDesc,
    encodedBatch,
  })

  console.log(`[solver] Bid submitted! Cadence tx: ${txId}`)
}

// ─────────────────────────────────────────────
// Polling loop
// ─────────────────────────────────────────────

/** Track which intents we've already bid on to avoid duplicate bids. */
const biddedIntents = new Set<number>()

async function poll(client: FlowIntentsClient): Promise<void> {
  console.log(`\n[solver] Polling for open intents at ${new Date().toISOString()}...`)

  let intents: Intent[]
  try {
    intents = await client.getOpenIntents()
  } catch (err) {
    console.error('[solver] Failed to fetch intents:', err)
    return
  }

  console.log(`[solver] Found ${intents.length} open intent(s)`)

  const swapIntents = intents.filter((i) => i.intentType === 'Swap')
  console.log(`[solver] ${swapIntents.length} are Swap intents`)

  for (const intent of swapIntents) {
    if (biddedIntents.has(intent.id)) {
      console.log(`[solver] Already bid on intent #${intent.id} — skipping`)
      continue
    }

    try {
      await processSwapIntent(client, intent)
      biddedIntents.add(intent.id)
    } catch (err) {
      console.error(`[solver] Error processing intent #${intent.id}:`, err)
    }
  }
}

// ─────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────

async function main() {
  if (!FLOW_ADDRESS || !FLOW_PRIVATE_KEY) {
    console.error('ERROR: Set FLOW_ADDRESS and FLOW_PRIVATE_KEY environment variables.')
    console.error('  FLOW_ADDRESS=0x...  FLOW_PRIVATE_KEY=<hex>  npx ts-node examples/swap-solver.ts')
    process.exit(1)
  }

  console.log('=== FlowIntents Swap Solver ===')
  console.log(`Account:  ${FLOW_ADDRESS}`)
  console.log(`Network:  mainnet`)
  console.log(`Strategy: WrapAndSwap (FLOW → WFLOW + stgUSDC via PunchSwap)`)
  console.log(`Poll:     every ${POLL_INTERVAL_MS / 1000}s`)
  console.log('================================\n')

  const client = new FlowIntentsClient({
    flowAddress: FLOW_ADDRESS,
    flowPrivateKey: FLOW_PRIVATE_KEY,
    // All other fields default to mainnet addresses
  })

  // Initial poll immediately
  await poll(client)

  // Then poll on interval
  setInterval(() => {
    poll(client).catch((err) => console.error('[solver] Poll error:', err))
  }, POLL_INTERVAL_MS)
}

main().catch((err) => {
  console.error('Fatal error:', err)
  process.exit(1)
})
