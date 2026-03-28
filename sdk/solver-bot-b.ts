/**
 * solver-bot-b.ts — "Conservative" solver bot for FlowIntents.
 *
 * Strategy:
 *   - YIELD intents: offers targetAPY - 0.5% (barely meets user target)
 *   - SWAP intents:  offers exact minAmountOut (no bonus)
 *   - Higher gas bid: 0.003 FLOW (takes more of the escrow)
 *   - Execution: ankr-stake (yield), punchswap-v2 (swap)
 *
 * This bot is intentionally less attractive than Bot-A — it demonstrates
 * competition. In a live market, Bot-B would rarely win unless Bot-A isn't
 * running or has a worse score for other reasons.
 *
 * Run:
 *   SOLVER_PK_B=<hex_key> SOLVER_ADDRESS_B=0x... SOLVER_EVM_ADDRESS_B=0x... \
 *     npx ts-node solver-bot-b.ts
 */

import { runSolverLoop, configureFCL } from './solver-lib'

// ── Config from environment ───────────────────────────────────────────────────

const SOLVER_PK = process.env.SOLVER_PK_B ?? process.env.BOT_B_PK ?? ''
const SOLVER_ADDRESS = process.env.SOLVER_ADDRESS_B ?? process.env.BOT_B_ADDRESS ?? ''
const SOLVER_EVM_ADDRESS = process.env.SOLVER_EVM_ADDRESS_B ?? process.env.BOT_B_EVM_ADDRESS ?? '0x0000000000000000000000000000000000000000'

if (!SOLVER_PK || !SOLVER_ADDRESS) {
  console.error('\x1b[31m[Bot-B] ERROR: SOLVER_PK_B and SOLVER_ADDRESS_B env vars are required.\x1b[0m')
  console.error('  export SOLVER_PK_B=<hex_private_key>')
  console.error('  export SOLVER_ADDRESS_B=0x...')
  console.error('  export SOLVER_EVM_ADDRESS_B=0x...  (optional)')
  process.exit(1)
}

// ── FCL config ────────────────────────────────────────────────────────────────

configureFCL()

// ── Launch ────────────────────────────────────────────────────────────────────

console.log('\x1b[35m╔══════════════════════════════════════════════════════╗\x1b[0m')
console.log('\x1b[35m║  FlowIntents Solver Bot B — CONSERVATIVE             ║\x1b[0m')
console.log('\x1b[35m║  Offers safe deals: -0.5% APY, exact swap amount     ║\x1b[0m')
console.log('\x1b[35m║  Gas bid: 0.003 FLOW (higher fee for solver)         ║\x1b[0m')
console.log('\x1b[35m╚══════════════════════════════════════════════════════╝\x1b[0m')

runSolverLoop({
  name: 'Bot-B',
  address: SOLVER_ADDRESS,
  privateKey: SOLVER_PK,
  evmAddress: SOLVER_EVM_ADDRESS,
  color: 'magenta',

  // Conservative bidding: offer LESS than what the user asked for
  yieldAPYBonus: -0.5,           // Yield: offer targetAPY - 0.5%
  swapAmountOutMultiplier: 1.0,  // Swap: offer exactly minAmountOut (no bonus)
  maxGasBid: 0.003,              // Higher gas bid — takes more from escrow
}).catch((err) => {
  console.error('\x1b[31m[Bot-B] Fatal error:\x1b[0m', err)
  process.exit(1)
})
