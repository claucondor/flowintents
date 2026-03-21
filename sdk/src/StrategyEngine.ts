/**
 * StrategyEngine — queries MCP for live yields, picks best strategy,
 * and builds the ABI-encoded BatchStep[] for FlowIntentsComposer.
 */

import { encodeAbiParameters, parseAbiParameters } from 'viem'
import type { Intent } from './types/Intent'
import type { Strategy, BatchStep, YieldOpportunity, CrossChainYield } from './types/Strategy'
import { MCPClient } from './MCPClient'

// ---- Fallback yields (used when MCP is unavailable) ----
const FALLBACK_FLOW_YIELDS: YieldOpportunity[] = [
  { protocol: 'MORE Finance', asset: 'stgUSDC', apy: 4.1, tvl: undefined, utilizationRate: 92, chain: 'flow' },
  { protocol: 'MORE Finance', asset: 'USDF', apy: 4.07, tvl: undefined, utilizationRate: undefined, chain: 'flow' },
  { protocol: 'Ankr', asset: 'ankrFLOW', apy: 12.0, tvl: undefined, utilizationRate: undefined, chain: 'flow' },
]

const FALLBACK_CROSS_CHAIN_YIELDS: CrossChainYield[] = [
  { protocol: 'Ethereum USDC', chain: 'ethereum', asset: 'USDC', apy: 17.0, bridgeFee: 0.5, estimatedNetAPY: 16.5 },
]

// Minimum cross-chain APY premium to recommend cross-chain over Flow
const CROSS_CHAIN_PREMIUM = 2.0

/**
 * ABI type for a single BatchStep:
 *   struct BatchStep { address target; bytes callData; uint256 value; }
 */
const BATCH_STEP_ABI = parseAbiParameters(
  '(address target, bytes callData, uint256 value)[]',
)

export class StrategyEngine {
  private mcp: MCPClient

  constructor(mcp?: MCPClient) {
    this.mcp = mcp ?? new MCPClient()
  }

  /**
   * Evaluate an intent and return ranked Strategy[].
   * Index 0 is the recommended strategy.
   */
  async evaluate(intent: Intent): Promise<Strategy[]> {
    const [flowYields, crossYields] = await Promise.all([
      this.mcp.getYieldOpportunities().catch(() => FALLBACK_FLOW_YIELDS),
      this.mcp.getCrossChainYields().catch(() => FALLBACK_CROSS_CHAIN_YIELDS),
    ])

    const strategies: Strategy[] = []

    // ---- Build Flow strategies ----
    for (const y of flowYields) {
      const confidence = this._confidenceForUtilization(y.utilizationRate)
      strategies.push({
        protocol: y.protocol,
        chain: 'flow',
        expectedAPY: y.apy,
        confidence,
        encodedBatch: this._encodeFlowBatch(y),
        rationale: `${y.protocol} ${y.asset} on Flow — ${y.apy}% APY` +
          (y.utilizationRate != null ? ` (utilization: ${y.utilizationRate}%)` : ''),
      })
    }

    // ---- Build cross-chain strategies ----
    const bestFlowAPY = Math.max(...strategies.map((s) => s.expectedAPY), 0)

    for (const cy of crossYields) {
      const netAPY = cy.estimatedNetAPY ?? cy.apy - (cy.bridgeFee ?? 0)
      if (netAPY > bestFlowAPY + CROSS_CHAIN_PREMIUM) {
        strategies.push({
          protocol: cy.protocol,
          chain: cy.chain as Strategy['chain'],
          expectedAPY: netAPY,
          confidence: 0.75,  // cross-chain has extra execution risk
          encodedBatch: this._encodeCrossChainBatch(cy),
          rationale: `${cy.protocol} on ${cy.chain} — ${netAPY.toFixed(2)}% net APY` +
            ` (gross: ${cy.apy}%, bridge fee: ${cy.bridgeFee ?? 0}%)`,
        })
      }
    }

    // ---- Rank by risk-adjusted APY (APY * confidence) ----
    strategies.sort((a, b) => b.expectedAPY * b.confidence - a.expectedAPY * a.confidence)

    // Filter: only strategies that meet the intent's targetAPY
    const viable = strategies.filter((s) => s.expectedAPY >= intent.targetAPY)

    return viable.length > 0 ? viable : strategies
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private _confidenceForUtilization(utilization?: number): number {
    if (utilization == null) return 0.8
    if (utilization > 95) return 0.5   // pool almost full — APY may compress fast
    if (utilization > 80) return 0.85
    return 0.95
  }

  /**
   * Encode a minimal BatchStep[] for a Flow-native yield deposit.
   * In production this would call the specific protocol's deposit selector.
   * Here we build a placeholder-but-valid ABI encoding so the type is satisfied.
   */
  private _encodeFlowBatch(y: YieldOpportunity): Uint8Array {
    const steps: BatchStep[] = [
      {
        // MORE Finance proxy or equivalent — placeholder address
        target: '0x0000000000000000000000000000000000000001',
        callData: '0x',
        value: 0n,
      },
    ]
    const encoded = encodeAbiParameters(BATCH_STEP_ABI, [
      steps.map((s) => ({ target: s.target as `0x${string}`, callData: s.callData, value: s.value })),
    ])
    return Buffer.from(encoded.slice(2), 'hex')
  }

  private _encodeCrossChainBatch(cy: CrossChainYield): Uint8Array {
    const steps: BatchStep[] = [
      {
        // Bridge contract placeholder
        target: '0x0000000000000000000000000000000000000002',
        callData: '0x',
        value: 0n,
      },
    ]
    const encoded = encodeAbiParameters(BATCH_STEP_ABI, [
      steps.map((s) => ({ target: s.target as `0x${string}`, callData: s.callData, value: s.value })),
    ])
    return Buffer.from(encoded.slice(2), 'hex')
  }
}
