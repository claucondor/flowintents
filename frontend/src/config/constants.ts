export const CADENCE_DEPLOYER = "0xc65395858a38d8ff";

export const ADDRESSES = {
  IntentMarketplaceV0_3: "0xc65395858a38d8ff",
  IntentExecutorV0_3: "0xc65395858a38d8ff",
  // V0_4 contracts (user-executed intent model)
  IntentMarketplaceV0_4: "0xc65395858a38d8ff",
  BidManagerV0_4: "0xc65395858a38d8ff",
  IntentExecutorV0_4: "0xc65395858a38d8ff",
  EVMBidRelay: "0x0f58eA537424C261FB55B45B77e5a25823077E05",
  FlowIntentsComposerV4: "0x5cc14D3509639a819f4e8f796128Fcc1C9576D95",
} as const;

export const FLOW_EVM_RPC = "https://mainnet.evm.nodes.onflow.org";
export const FLOW_ACCESS_NODE = "https://rest-mainnet.onflow.org";
export const FLOW_CHAIN_ID = 747; // Flow EVM mainnet

export const TOKENS = {
  FLOW: {
    symbol: "FLOW",
    name: "Flow",
    emoji: "🌊",
    decimals: 8,
    color: "#00EF8B",
  },
  WFLOW: {
    symbol: "WFLOW",
    name: "Wrapped FLOW",
    emoji: "💧",
    decimals: 18,
    color: "#06B6D4",
  },
  stgUSDC: {
    symbol: "stgUSDC",
    name: "Stargate USDC",
    emoji: "💵",
    decimals: 6,
    color: "#3B82F6",
  },
} as const;

export const STATS = {
  totalIntents: "2,847",
  totalVolume: "$4.2M",
  activeSolvers: "12",
};

export const GAS_ESCROW_AMOUNT = 0.01;

// V0_4: Commission escrow (separate from gas escrow concept)
export const COMMISSION_ESCROW_AMOUNT = 0.01;

// EVM token addresses on Flow EVM mainnet (chainId 747)
export const EVM_TOKEN_ADDRESSES = {
  WFLOW: "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e",
  stgUSDC: "0xF1815bd50389c46847f0Bda824eC8da914045D14",
} as const;

// V0_4 DeliverySide enum values (mirrors Cadence enum)
export const DELIVERY_SIDE = {
  CadenceVault: 0,
  COA: 1,
  ExternalEVM: 2,
  ExternalCadence: 3,
} as const;

export type DeliverySideKey = keyof typeof DELIVERY_SIDE;

export const DELIVERY_SIDE_LABELS: Record<DeliverySideKey, string> = {
  CadenceVault: "Cadence Vault (bridge back)",
  COA: "My COA (EVM)",
  ExternalEVM: "External EVM Address",
  ExternalCadence: "External Cadence Address",
};

export const DURATION_OPTIONS = [
  { label: "7d", days: 7 },
  { label: "30d", days: 30 },
  { label: "90d", days: 90 },
] as const;
