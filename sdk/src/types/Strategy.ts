export interface Strategy {
  protocol: string
  chain: 'flow' | 'ethereum' | 'base' | 'arbitrum'
  expectedAPY: number
  confidence: number  // 0-1
  encodedBatch: Uint8Array  // ABI-encoded BatchStep[] for FlowIntentsComposer
  rationale: string
}

// ---- MCP response types ----

export interface YieldOpportunity {
  protocol: string
  asset: string
  apy: number
  tvl?: number
  utilizationRate?: number
  chain: string
}

export interface CrossChainYield {
  protocol: string
  chain: string
  asset: string
  apy: number
  bridgeFee?: number
  estimatedNetAPY?: number
}

export interface RouteResult {
  fromToken: string
  toToken: string
  amount: string
  expectedOut: string
  priceImpact: number
  route: string[]
}

export interface SlippageMatrix {
  pairs: Record<string, Record<string, number>>  // token -> token -> slippage bps
}

// ---- ABI encoding types ----

export interface BatchStep {
  target: string        // contract address
  callData: `0x${string}`
  value: bigint
  required?: boolean    // whether step failure aborts the batch (default: true)
}
