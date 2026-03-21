/**
 * solver.config.ts — THE ONLY FILE YOU NEED TO EDIT.
 *
 * Fill in your credentials and bidding strategy.
 * The SDK reads this at startup and handles everything else.
 */

import type { SolverConfig } from './src/types/SolverConfig'

const config: SolverConfig = {
  // ---- Flow Cadence (for submitting bids on-chain) ----
  flowPrivateKey: 'YOUR_FLOW_PRIVATE_KEY_HEX',   // hex, no 0x prefix
  flowAddress: '0xYOUR_FLOW_ADDRESS',

  // ---- Flow EVM / chainId 747 (for ERC-8004 registration) ----
  evmPrivateKey: 'YOUR_EVM_PRIVATE_KEY_HEX',     // hex, no 0x prefix
  evmAddress: '0xYOUR_EVM_ADDRESS',

  // agentTokenId is auto-populated after the first registerAgent() call.
  // Leave undefined on first run.
  // agentTokenId: 42,

  // ---- Bidding strategy ----
  /** Do NOT bid on intents requesting less than this APY (%) */
  minAPYThreshold: 3.0,

  /** Maximum USDC you're willing to commit (UFix64 string — must have 8 decimals) */
  maxPrincipal: '5000.00000000',

  // ---- Optional AI strategy (OpenRouter) ----
  // openRouterApiKey: 'sk-or-...',
}

export default config
