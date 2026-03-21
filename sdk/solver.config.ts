/**
 * solver.config.ts — THE ONLY FILE YOU NEED TO EDIT.
 *
 * Fill in your credentials and bidding strategy.
 * The SDK reads this at startup and handles everything else.
 *
 * Quick-start steps:
 *   1. Fill in flowPrivateKey + flowAddress (Flow Cadence account).
 *   2. Fill in evmPrivateKey + evmAddress (Flow EVM / chainId 747 account).
 *   3. Call Executor.registerSolver() once — this mints your ERC-8004 agent token.
 *   4. Copy the printed tokenId into agentTokenId below so it is not re-fetched every run.
 *   5. Adjust minAPYThreshold and maxPrincipal to match your risk appetite.
 */

import type { SolverConfig } from './src/types/SolverConfig'

const config: SolverConfig = {
  // ---- Flow Cadence (for submitting bids on-chain via FCL) ----

  /** Your Flow account private key — hex encoded, NO 0x prefix. */
  flowPrivateKey: 'YOUR_FLOW_PRIVATE_KEY_HEX',

  /** Your Flow account address — WITH 0x prefix (e.g. "0xabcdef01234567890"). */
  flowAddress: '0xYOUR_FLOW_ADDRESS',

  // ---- Flow EVM / chainId 747 (for ERC-8004 agent registration) ----

  /** Your Flow EVM private key — hex encoded, NO 0x prefix. */
  evmPrivateKey: 'YOUR_EVM_PRIVATE_KEY_HEX',

  /** Your Flow EVM address — WITH 0x prefix (e.g. "0xAbCd..."). */
  evmAddress: '0xYOUR_EVM_ADDRESS',

  /**
   * agentTokenId — your ERC-8004 Agent NFT token ID on Flow EVM (chainId 747).
   *
   * AUTO-POPULATED: leave undefined on the first run. After calling
   * Executor.registerSolver() (which calls ERC8004Manager.registerAgent()
   * internally), copy the printed token ID here so the SDK does not query
   * the chain on every startup.
   *
   * Example after registration:
   *   agentTokenId: 42,
   */
  // agentTokenId: 42,

  // ---- Bidding strategy ----

  /**
   * minAPYThreshold — minimum APY (%) the solver is willing to bid for.
   *
   * Intents with targetAPY below this value are skipped entirely.
   * Set conservatively: bidding on very low-APY intents may not be profitable
   * after gas and bridge fees.
   *
   * Example: 3.0 means skip any intent requesting less than 3% APY.
   */
  minAPYThreshold: 3.0,

  /**
   * maxPrincipal — maximum USDC principal you are willing to commit per intent.
   *
   * MUST be a UFix64 string with exactly 8 decimal places (Flow requirement).
   * Example: "5000.00000000" = five thousand USDC.
   */
  maxPrincipal: '5000.00000000',

  // ---- Optional: AI-powered strategy selection via OpenRouter ----
  // openRouterApiKey: 'sk-or-...',
}

export default config
