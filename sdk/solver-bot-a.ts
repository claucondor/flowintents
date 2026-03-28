/**
 * solver-bot-a.ts — "Aggressive" solver bot for FlowIntents.
 *
 * Strategy:
 *   - YIELD intents: offers targetAPY + 1.5% (beats user target significantly)
 *   - SWAP intents:  offers minAmountOut * 1.02 (2% bonus over minimum)
 *   - Low gas bid: 0.001 FLOW (competitive, user gets more of escrow back)
 *   - Execution: ankr-stake (yield), punchswap-v2 (swap)
 *
 * Run:
 *   SOLVER_PK=<hex_key> SOLVER_ADDRESS=0x... SOLVER_EVM_ADDRESS=0x... \
 *     npx ts-node solver-bot-a.ts
 */

import { runSolverLoop, configureFCL } from './solver-lib'

// ── Config from environment ───────────────────────────────────────────────────

const SOLVER_PK = process.env.SOLVER_PK ?? process.env.BOT_A_PK ?? ''
const SOLVER_ADDRESS = process.env.SOLVER_ADDRESS ?? process.env.BOT_A_ADDRESS ?? ''
const SOLVER_EVM_ADDRESS = process.env.SOLVER_EVM_ADDRESS ?? process.env.BOT_A_EVM_ADDRESS ?? '0x0000000000000000000000000000000000000000'

if (!SOLVER_PK || !SOLVER_ADDRESS) {
  console.error('\x1b[31m[Bot-A] ERROR: SOLVER_PK and SOLVER_ADDRESS env vars are required.\x1b[0m')
  console.error('  export SOLVER_PK=<hex_private_key>')
  console.error('  export SOLVER_ADDRESS=0x...')
  console.error('  export SOLVER_EVM_ADDRESS=0x...  (optional, for EVM output routing)')
  process.exit(1)
}

// ── FCL config ────────────────────────────────────────────────────────────────

configureFCL()

// ── Launch ────────────────────────────────────────────────────────────────────

console.log('\x1b[34m╔══════════════════════════════════════════════════════╗\x1b[0m')
console.log('\x1b[34m║  FlowIntents Solver Bot A — AGGRESSIVE               ║\x1b[0m')
console.log('\x1b[34m║  Offers best deals: +1.5% APY, +2% swap bonus        ║\x1b[0m')
console.log('\x1b[34m║  Gas bid: 0.001 FLOW (low — attracts winners)        ║\x1b[0m')
console.log('\x1b[34m╚══════════════════════════════════════════════════════╝\x1b[0m')

runSolverLoop({
  name: 'Bot-A',
  address: SOLVER_ADDRESS,
  privateKey: SOLVER_PK,
  evmAddress: SOLVER_EVM_ADDRESS,
  color: 'cyan',

  // Aggressive bidding: offer MORE than what the user asked for
  yieldAPYBonus: +1.5,           // Yield: offer targetAPY + 1.5%
  swapAmountOutMultiplier: 1.02, // Swap: offer minAmountOut * 1.02 (2% better)
  maxGasBid: 0.001,              // Low gas bid — keeps more in escrow for user
}).catch((err) => {
  console.error('\x1b[31m[Bot-A] Fatal error:\x1b[0m', err)
  process.exit(1)
})
