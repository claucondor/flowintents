/**
 * types.ts — FlowIntents SDK core TypeScript types.
 *
 * Matches exactly the Cadence contract structs in:
 *   - cadence/contracts/IntentMarketplaceV0_3.cdc
 *   - cadence/contracts/BidManagerV0_3.cdc
 */

// ─────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────

/** Default on-chain addresses — all overridable via FlowIntentsClient config. */
export const DEFAULT_CONFIG = {
  /** Cadence account that deployed IntentMarketplaceV0_3, BidManagerV0_3, etc. */
  cadenceAddress: '0xc65395858a38d8ff',
  /** FlowIntentsComposerV4 on Flow EVM (chainId 747) */
  composerV4: '0x5cc14D3509639a819f4e8f796128Fcc1C9576D95',
  /** EVMBidRelay on Flow EVM */
  evmBidRelay: '0x0f58eA537424C261FB55B45B77e5a25823077E05',
  /** Flow EVM JSON-RPC endpoint */
  flowEVMRpc: 'https://mainnet.evm.nodes.onflow.org',
  /** Flow Cadence access node (REST) */
  flowAccessNode: 'https://rest-mainnet.onflow.org',
} as const

/** Known ERC-20 / protocol token addresses on Flow EVM mainnet (chainId 747). */
export const TOKENS = {
  /** Wrapped FLOW (WFLOW) */
  WFLOW: '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e',
  /** Stargate USDC (stgUSDC) */
  stgUSDC: '0xF1815bd50389c46847f0Bda824eC8da914045D14',
  /** Ankr Staked FLOW EVM (bond token; stakeBonds() paused — use ANKR_CERT_TOKEN instead) */
  ankrFLOW: '0x1b97100eA1D7126C4d60027e231EA4CB25314bdb',
  /** Ankr Reward Earning FLOW EVM cert token (aFLOWEVMb — from stakeCerts()) */
  ANKR_CERT_TOKEN: '0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A',
  /** MORE Protocol pool token */
  MOREPool: '0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d',
  /** PunchSwap UniV2-style router */
  PUNCH_ROUTER: '0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d',
  /** USDF (USD Flow / PYUSD0 bridged) */
  USDF: '0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED',
  /** AlphaYield WFLOW Vault (ERC-4626) */
  ALPHA_WFLOW_VAULT: '0xcbf9a7753f9d2d0e8141ebb36d99f87acef98597',
  /** Ankr FlowStakingPool proxy */
  ANKR_STAKING_POOL: '0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a',
} as const

// ─────────────────────────────────────────────
// Intent types (matches IntentMarketplaceV0_3)
// ─────────────────────────────────────────────

export type IntentType = 'Yield' | 'Swap' | 'BridgeYield'

export type IntentStatus =
  | 'Open'        // 0 — accepting bids
  | 'BidSelected' // 1 — winner chosen, awaiting execution
  | 'Active'      // 2 — strategy running on-chain
  | 'Completed'   // 3 — funds returned, intent fulfilled
  | 'Cancelled'   // 4 — owner cancelled before execution
  | 'Expired'     // 5 — passed expiryBlock without execution

export type PrincipalSide = 'cadence' | 'evm'

/**
 * Intent — a user's on-chain intent on IntentMarketplaceV0_3.
 *
 * Numbers that are UFix64 on-chain are represented as JS `number` (float).
 * Large UInt256 EVM amounts are `bigint`.
 */
export interface Intent {
  /** Intent ID (UInt64) */
  id: number
  /** Cadence address of the intent owner */
  intentOwner: string
  /** Deposited principal in FLOW or token units (UFix64) */
  principalAmount: number
  /** Yield, Swap, or BridgeYield */
  intentType: IntentType
  /** Target APY (percentage, e.g. 8.0 = 8%). Relevant for Yield/BridgeYield intents. */
  targetAPY: number
  /** Minimum acceptable swap output (UFix64). Swap intents only. */
  minAmountOut?: number
  /** Maximum acceptable fee in basis points (e.g. 30 = 0.3%). Swap intents only. */
  maxFeeBPS?: number
  /** Minimum APY for BridgeYield intents. */
  minAPY?: number
  /** Duration the intent should run, in days. */
  durationDays: number
  /** Block height after which the intent expires. */
  expiryBlock: number
  /** Current lifecycle status. */
  status: IntentStatus
  /** Whether funds originate from the Cadence or EVM side. */
  principalSide: PrincipalSide
  /** Optional EVM address to receive output tokens ("swap and send"). */
  recipientEVMAddress?: string
  /** Winning bid ID once BidManagerV0_3 selects a winner. */
  winningBidID?: number
  /** Timestamp when the intent was created (UFix64, seconds). */
  createdAt: number
  /** Block height by which the solver must execute (createdAt + 1000 blocks). */
  executionDeadlineBlock: number
  /** Gas escrow balance deposited by the user (UFix64 FLOW). */
  gasEscrowBalance: number
  // EVM-side intent fields (principalSide === 'evm')
  evmIntentId?: bigint
  evmToken?: string
  evmAmount?: bigint
}

// ─────────────────────────────────────────────
// Bid types (matches BidManagerV0_3)
// ─────────────────────────────────────────────

/**
 * Bid — a solver's offer on IntentMarketplaceV0_3.
 */
export interface Bid {
  /** Bid ID (UInt64) */
  id: number
  /** The intent this bid targets */
  intentID: number
  /** Cadence address of the solver */
  solverAddress: string
  /** EVM address of the solver */
  solverEVMAddress: string
  /** Offered APY (for Yield/BridgeYield). nil for Swap bids. */
  offeredAPY?: number
  /** Offered amount out (for Swap). nil for Yield/BridgeYield bids. */
  offeredAmountOut?: number
  /** Estimated fee in basis points. Optional. */
  estimatedFeeBPS?: number
  /** Target chain for BridgeYield (e.g. "ethereum", "base"). nil = Flow-native. */
  targetChain?: string
  /** Max gas the solver requests from the user's escrow (UFix64 FLOW). */
  maxGasBid: number
  /** Human-readable strategy description. */
  strategy: string
  /** ABI-encoded BatchStep[] as hex string (0x-prefixed). */
  encodedBatch: string
  /** Timestamp of bid submission (UFix64, seconds). */
  submittedAt: number
  /** Combined bid score computed by BidManagerV0_3. */
  score: number
}

/**
 * Parameters for submitting a new bid.
 */
export interface BidParams {
  /** The intent to bid on. */
  intentID: number
  /** Offered APY for Yield/BridgeYield intents (percentage, e.g. 8.5). */
  offeredAPY?: number
  /** Offered amount out for Swap intents (UFix64). */
  offeredAmountOut?: number
  /** Estimated fee in basis points. */
  estimatedFeeBPS?: number
  /** Target chain for BridgeYield (nil = Flow-native). */
  targetChain?: string
  /** Max gas escrow the solver requests in FLOW (e.g. 0.01). */
  maxGasBid: number
  /** Human-readable strategy description. */
  strategy: string
  /** ABI-encoded BatchStep[] — use the `strategies` module to build this. */
  encodedBatch: string
}

// ─────────────────────────────────────────────
// Strategy / EVM encoding types
// ─────────────────────────────────────────────

/**
 * A single step in an EVM strategy batch (StrategyStep in FlowIntentsComposerV4.sol).
 */
export interface StrategyStep {
  /** Protocol ID (0=MORE, 1=STARGATE, 2=LAYERZERO, 3=WFLOW_WRAP, 4=CUSTOM, 5=ANKR_STAKE) */
  protocol: number
  /** Contract to call */
  target: string
  /** ABI-encoded call data */
  callData: `0x${string}`
  /** Native FLOW value in attoFLOW (1 FLOW = 1e18) */
  value: bigint
}

// ─────────────────────────────────────────────
// SDK config
// ─────────────────────────────────────────────

export interface FlowIntentsConfig {
  /** Cadence account address that deployed all V0_3 contracts. */
  cadenceAddress?: string
  /** FlowIntentsComposerV4 EVM contract address. */
  composerV4?: string
  /** EVMBidRelay EVM contract address. */
  evmBidRelay?: string
  /** Flow EVM JSON-RPC endpoint. */
  flowEVMRpc?: string
  /** Flow Cadence REST access node. */
  flowAccessNode?: string
  /**
   * Cadence private key for signing transactions (hex, no 0x prefix).
   * Required for submitBid() and executeIntent().
   */
  flowPrivateKey?: string
  /** Cadence account address that matches the private key (0x-prefixed). */
  flowAddress?: string
  /** Key index to use when signing Cadence transactions (default: 0). */
  keyIndex?: number
}
