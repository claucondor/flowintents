/**
 * config.ts — Protocol addresses and bot settings for the FlowIntents solver bot.
 *
 * All addresses are Flow EVM mainnet (chainId 747) unless otherwise noted.
 */

// ─── Flow EVM Mainnet Addresses ──────────────────────────────────────────────

export const EVM_ADDRESSES = {
  /** Wrapped FLOW token */
  WFLOW: "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e",

  /** Stargate USDC on Flow EVM */
  STG_USDC: "0xF1815bd50389c46847f0Bda824eC8da914045D14",

  /** PunchSwap UniswapV2-style router */
  PUNCHSWAP_ROUTER: "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d",

  /** MORE Finance pool (Aave v3 fork) */
  MORE_POOL: "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d",

  /** mFlowWFLOW — MORE yield token for WFLOW deposits */
  MORE_WFLOW_TOKEN: "0x02BF4bd075c1b7C8D85F54777eaAA3638135c059",

  /** Ankr FlowStakingPool proxy */
  ANKR_STAKING_POOL: "0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a",

  /** Ankr cert token — aFLOWEVMb */
  ANKR_CERT_TOKEN: "0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A",
} as const;

// ─── ABI Selectors ────────────────────────────────────────────────────────────

export const SELECTORS = {
  WFLOW_DEPOSIT: "0xd0e30db0",                   // WFLOW.deposit()
  ERC20_APPROVE: "0x095ea7b3",                   // approve(address,uint256)
  PUNCHSWAP_SWAP: "0x38ed1739",                  // swapExactTokensForTokens(...)
  MORE_DEPOSIT: "0xe8eda9df",                    // deposit(address,uint256,address,uint16) Aave v2
  MORE_SUPPLY: "0x617ba037",                     // supply(address,uint256,address,uint16) Aave v3
  ANKR_STAKE_CERTS: "0xac76d450",               // stakeCerts() — payable, no args
} as const;

// ─── Cadence / Flow Mainnet Addresses ────────────────────────────────────────

export const CADENCE_ADDRESSES = {
  /** Deployer — all FlowIntents contracts */
  DEPLOYER: "0xc65395858a38d8ff",
  FLOW_REST_API: "https://rest-mainnet.onflow.org",
} as const;

// ─── Bot Settings ─────────────────────────────────────────────────────────────

export const BOT_CONFIG = {
  /** Model for Claude — fast and cheap for a polling bot */
  CLAUDE_MODEL: "claude-haiku-4-5-20251001",

  /** How often the bot polls for open intents (ms) */
  POLL_INTERVAL_MS: parseInt(process.env.POLL_INTERVAL_MS ?? "30000", 10),

  /** When true: log everything but do NOT submit real transactions */
  DRY_RUN: process.env.DRY_RUN !== "false",

  /** Flow network name for the CLI signer */
  FLOW_NETWORK: process.env.FLOW_NETWORK ?? "mainnet",

  /** Cadence address of the solver account (0x-prefixed) */
  SOLVER_CADENCE_ADDRESS:
    process.env.SOLVER_CADENCE_ADDRESS ?? "0xc65395858a38d8ff",

  /** Absolute path to the flowintents repo root */
  REPO_ROOT: "/home/oydual3/hackaflow/flowintents",
} as const;

// ─── Strategy Protocol IDs (match StrategyStep.protocol in Solidity) ─────────

export const PROTOCOL_ID = {
  MORE: 0,
  CUSTOM: 4,  // Generic ERC-20 calls (approve, deposit, swap)
  ANKR_STAKE: 5,
} as const;
