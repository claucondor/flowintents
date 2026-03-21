/**
 * SolverConfig — THE ONLY FILE THE USER EDITS.
 * Fill in your credentials and strategy parameters.
 */
export interface SolverConfig {
  /** Flow Cadence private key (hex, no 0x prefix) */
  flowPrivateKey: string
  /** Flow Cadence account address (0x-prefixed) */
  flowAddress: string
  /** Flow EVM (chainId 747) private key (hex, no 0x prefix) */
  evmPrivateKey: string
  /** Flow EVM address (0x-prefixed) */
  evmAddress: string
  /** ERC-8004 Agent token ID — auto-populated after first registerAgent() call */
  agentTokenId?: number
  /** Minimum APY percentage to place a bid (e.g. 3.5 means 3.5%) */
  minAPYThreshold: number
  /** Maximum USDC principal the solver is willing to commit (UFix64 string, e.g. "10000.00000000") */
  maxPrincipal: string
  /** Optional OpenRouter API key for AI-powered strategy selection */
  openRouterApiKey?: string
}
