// ─────────────────────────────────────────────
// FlowIntents Solver SDK — main exports
// ─────────────────────────────────────────────

// ---- Core client (primary V0_3 entry point) ----
export { FlowIntentsClient } from './client'

// ---- V0_3 types ----
export type {
  Intent,
  Bid,
  BidParams,
  StrategyStep,
  FlowIntentsConfig,
  IntentType,
  IntentStatus,
  PrincipalSide,
} from './types'
export { DEFAULT_CONFIG, TOKENS } from './types'

// ---- V0_3 read functions ----
export { getOpenIntents, getOpenIntentIds, getIntent } from './intents'

// ---- V0_3 bid functions ----
export {
  getBid,
  getWinningBid,
  submitBid,
  buildAuthorization,
  uint8ArrayToHex,
  hexToUint8Array,
} from './bids'

// ---- V0_3 strategy encoders ----
export {
  encodeWrapFlowStrategy,
  encodeWrapAndSwapStrategy,
  encodeANKRStakeStrategy,
  encodeCustomStrategy,
  flowToAtto,
  PROTOCOL,
} from './strategies'

// ---- Legacy V0_1 types (kept for backwards compatibility) ----
export * from './types/Intent'
export * from './types/SolverConfig'
export * from './types/Strategy'

// ---- Legacy V0_1 modules ----
export { MCPClient } from './MCPClient'
export { StrategyEngine } from './StrategyEngine'
export { ERC8004Manager, flowEvmMainnet, flowEvmEmulator } from './ERC8004Manager'
export { EventListener } from './EventListener'
export { buildBidArgs, strategyToBidArgs, toUFix64 } from './BidBuilder'
export type { BidArgs } from './BidBuilder'
export { Executor } from './Executor'
