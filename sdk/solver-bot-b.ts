/**
 * solver-bot-b.ts — "Multi-Hop" solver bot for FlowIntents V0_4.
 *
 * Strategy:
 *   - SWAP intents: WFLOW → USDF → stgUSDC via PunchSwap multi-hop
 *   - YIELD intents: Ankr stake (same as Bot A)
 *   - Competes with Bot A which uses direct WFLOW → stgUSDC
 *
 * Run:
 *   SOLVER_PK=<hex_key> SOLVER_ADDRESS=0x... \
 *     npx tsx solver-bot-b.ts
 */

import {
  configureFCL,
  log,
  getOpenIntentIds,
  getIntent,
  getBidsBySolver,
  submitBidTx,
  getPunchSwapMultiHopQuote,
  getCurrentBlockHeight,
  COMPOSER_V5,
  POLL_INTERVAL_MS,
} from './solver-lib'
import { encodeMultiHopSwapStrategy, encodeAlphaYieldStrategy } from './src/strategies'
import { TOKENS } from './src/types'

// ── Config ───────────────────────────────────────────────────────────────────

const SOLVER_PK = process.env.SOLVER_PK ?? process.env.BOT_B_PK ?? ''
const SOLVER_ADDRESS = process.env.SOLVER_ADDRESS ?? process.env.BOT_B_ADDRESS ?? ''

if (!SOLVER_PK || !SOLVER_ADDRESS) {
  console.error('\x1b[31m[Bot-B] ERROR: SOLVER_PK and SOLVER_ADDRESS env vars required.\x1b[0m')
  process.exit(1)
}

configureFCL()

// ── Launch ───────────────────────────────────────────────────────────────────

console.log('\x1b[35m╔══════════════════════════════════════════════════════╗\x1b[0m')
console.log('\x1b[35m║  FlowIntents Solver Bot B — MULTI-HOP + ALPHA YIELD  ║\x1b[0m')
console.log('\x1b[35m║  Swap: WFLOW → USDF → stgUSDC via PunchSwap          ║\x1b[0m')
console.log('\x1b[35m║  Yield: AlphaYield WFLOW Vault (ERC-4626)            ║\x1b[0m')
console.log('\x1b[35m║  Gas bid: 0.002 FLOW                                 ║\x1b[0m')
console.log('\x1b[35m╚══════════════════════════════════════════════════════╝\x1b[0m')

const MAX_GAS_BID = 0.002
const biddedIntents = new Set<number>()

async function tick() {
  try {
    const currentBlock = await getCurrentBlockHeight()
    const openIds = await getOpenIntentIds()
    log('magenta', 'Bot-B', `Poll — block ${currentBlock} — ${openIds.length} open intent(s)`)

    for (const intentId of openIds) {
      if (biddedIntents.has(intentId)) continue

      const intent = await getIntent(intentId)
      if (!intent || intent.status !== 'Open') continue

      try {
        if (intent.intentType === 'Yield') {
          // AlphaYield WFLOW Vault — ERC-4626
          const offeredAPY = 5.0 // AlphaYield competitive rate
          const batch = encodeAlphaYieldStrategy(intent.principalAmount, COMPOSER_V5)
          log('magenta', 'Bot-B', `  AlphaYield: ${intent.principalAmount} FLOW → syWFLOWv (~${offeredAPY}% APY)`)
          const txId = await submitBidTx({
            intentID: intentId,
            offeredAPY,
            maxGasBid: MAX_GAS_BID,
            strategy: 'alphayield-wflow-vault',
            encodedBatch: batch,
          }, SOLVER_ADDRESS, SOLVER_PK)
          biddedIntents.add(intentId)
          log('green', 'Bot-B', `  Bid submitted — tx: ${txId.slice(0, 16)}…`)

        } else if (intent.intentType === 'Swap') {
          // Multi-hop: WFLOW → USDF → stgUSDC
          const quoteRaw = await getPunchSwapMultiHopQuote(
            intent.principalAmount, TOKENS.USDF, TOKENS.stgUSDC
          )
          const offeredAmountOut = Number(quoteRaw) / 1e6
          const swapMinOut = BigInt(Math.floor(Number(quoteRaw) * 0.95))

          log('magenta', 'Bot-B', `  Multi-hop quote: ${intent.principalAmount} FLOW → USDF → ${offeredAmountOut.toFixed(6)} stgUSDC`)

          const batch = encodeMultiHopSwapStrategy(
            intent.principalAmount,
            TOKENS.USDF,
            TOKENS.stgUSDC,
            COMPOSER_V5,
            swapMinOut,
          )

          const txId = await submitBidTx({
            intentID: intentId,
            offeredAmountOut,
            maxGasBid: MAX_GAS_BID,
            strategy: 'multihop-wflow-usdf-stgusdc',
            encodedBatch: batch,
          }, SOLVER_ADDRESS, SOLVER_PK)
          biddedIntents.add(intentId)
          log('green', 'Bot-B', `  Bid submitted — tx: ${txId.slice(0, 16)}… offeredOut: ${offeredAmountOut.toFixed(6)} stgUSDC`)

        } else {
          log('gray', 'Bot-B', `  Skipping intent #${intentId} (unsupported type)`)
          biddedIntents.add(intentId)
        }
      } catch (err) {
        log('red', 'Bot-B', `  Bid failed for intent #${intentId}: ${(err as Error).message?.slice(0, 200) ?? err}`)
        if (String(err).includes('already') || String(err).includes('duplicate')) {
          biddedIntents.add(intentId)
        }
      }
    }
  } catch (err) {
    log('red', 'Bot-B', `Poll error: ${err}`)
  }
}

// Run
tick().then(() => setInterval(tick, POLL_INTERVAL_MS))
