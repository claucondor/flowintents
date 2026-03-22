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

// WFLOW contract on Flow EVM (emulator and mainnet)
const WFLOW_ADDRESS = '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e' as `0x${string}`
// WFLOW.deposit() selector
const WFLOW_DEPOSIT_SELECTOR = '0xd0e30db0' as `0x${string}`

/**
 * ABI type for a single BatchStep:
 *   struct BatchStep { address target; bytes callData; uint256 value; bool required; }
 */
const BATCH_STEP_ABI = parseAbiParameters(
  '(address target, bytes callData, uint256 value, bool required)[]',
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
   * Encode a BatchStep[] for a Flow-native yield deposit.
   *
   * For WFLOW / ankrFLOW: encode as WFLOW.deposit() (selector 0xd0e30db0).
   * The value will be filled at execution time from the intent principalAmount;
   * here we encode 0 as the value placeholder since the Cadence executor sets it.
   *
   * For other Flow protocols (MORE Finance, etc.): use a placeholder step that
   * passes the call data through to FlowIntentsComposer.
   */
  private _encodeFlowBatch(y: YieldOpportunity): Uint8Array {
    let steps: BatchStep[]

    if (y.asset.toLowerCase().includes('flow') || y.protocol.toLowerCase().includes('ankr')) {
      // WFLOW.deposit() — wraps FLOW into WFLOW for yield
      steps = [
        {
          target: WFLOW_ADDRESS,
          callData: WFLOW_DEPOSIT_SELECTOR,
          value: 0n,
          required: true,
        },
      ]
    } else {
      // Generic yield protocol deposit — placeholder; real selector added per protocol
      steps = [
        {
          target: '0x0000000000000000000000000000000000000001',
          callData: '0x',
          value: 0n,
          required: true,
        },
      ]
    }

    const encoded = encodeAbiParameters(BATCH_STEP_ABI, [
      steps.map((s) => ({
        target: s.target as `0x${string}`,
        callData: s.callData,
        value: s.value,
        required: (s as BatchStep & { required?: boolean }).required ?? true,
      })),
    ])
    return Buffer.from(encoded.slice(2), 'hex')
  }

  private _encodeCrossChainBatch(cy: CrossChainYield): Uint8Array {
    const steps: BatchStep[] = [
      {
        // Bridge contract placeholder — real address varies per destination
        target: '0x0000000000000000000000000000000000000002',
        callData: '0x',
        value: 0n,
        required: true,
      },
    ]
    const encoded = encodeAbiParameters(BATCH_STEP_ABI, [
      steps.map((s) => ({
        target: s.target as `0x${string}`,
        callData: s.callData,
        value: s.value,
        required: (s as BatchStep & { required?: boolean }).required ?? true,
      })),
    ])
    return Buffer.from(encoded.slice(2), 'hex')
  }
}
