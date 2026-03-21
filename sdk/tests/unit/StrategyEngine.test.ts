import { describe, it, expect, vi, beforeEach } from 'vitest'
import { StrategyEngine } from '../../src/StrategyEngine'
import { MCPClient } from '../../src/MCPClient'
import type { Intent } from '../../src/types/Intent'
import type { YieldOpportunity, CrossChainYield } from '../../src/types/Strategy'

const mockIntent: Intent = {
  id: '1',
  owner: '0xabc',
  tokenType: 'USDC',
  principalAmount: '1000.00000000',
  targetAPY: 4.0,
  durationDays: 30,
  expiryBlock: 99999,
  status: 'Open',
  createdAt: 1700000000,
}

describe('StrategyEngine', () => {
  let engine: StrategyEngine
  let mockMCP: MCPClient

  beforeEach(() => {
    mockMCP = {
      getYieldOpportunities: vi.fn(),
      getCrossChainYields: vi.fn(),
      simulateBestRoute: vi.fn(),
      getPrices: vi.fn(),
      getSlippageMatrix: vi.fn(),
      callTool: vi.fn(),
    } as unknown as MCPClient

    engine = new StrategyEngine(mockMCP)
  })

  it('returns strategies sorted by risk-adjusted APY', async () => {
    const flowYields: YieldOpportunity[] = [
      { protocol: 'MORE Finance', asset: 'stgUSDC', apy: 4.1, utilizationRate: 92, chain: 'flow' },
      { protocol: 'Ankr', asset: 'ankrFLOW', apy: 12.0, utilizationRate: 60, chain: 'flow' },
    ]
    const crossYields: CrossChainYield[] = []

    vi.mocked(mockMCP.getYieldOpportunities).mockResolvedValue(flowYields)
    vi.mocked(mockMCP.getCrossChainYields).mockResolvedValue(crossYields)

    const strategies = await engine.evaluate(mockIntent)
    expect(strategies.length).toBeGreaterThan(0)
    // Best strategy should be first
    expect(strategies[0]!.expectedAPY).toBeGreaterThanOrEqual(strategies[1]?.expectedAPY ?? 0)
  })

  it('includes cross-chain strategy only when premium > 2%', async () => {
    const flowYields: YieldOpportunity[] = [
      { protocol: 'MORE Finance', asset: 'stgUSDC', apy: 4.1, chain: 'flow' },
    ]
    const crossYields: CrossChainYield[] = [
      // This one qualifies: 17% >> 4.1% + 2%
      { protocol: 'Ethereum USDC', chain: 'ethereum', asset: 'USDC', apy: 17.0, bridgeFee: 0.5, estimatedNetAPY: 16.5 },
      // This one does NOT qualify: net 5.5% is not > 4.1% + 2% = 6.1%
      { protocol: 'SmallYield', chain: 'base', asset: 'USDC', apy: 6.0, bridgeFee: 0.5, estimatedNetAPY: 5.5 },
    ]

    vi.mocked(mockMCP.getYieldOpportunities).mockResolvedValue(flowYields)
    vi.mocked(mockMCP.getCrossChainYields).mockResolvedValue(crossYields)

    const strategies = await engine.evaluate(mockIntent)
    const crossChain = strategies.filter((s) => s.chain !== 'flow')
    expect(crossChain).toHaveLength(1)
    expect(crossChain[0]!.protocol).toBe('Ethereum USDC')
  })

  it('falls back to hardcoded yields when MCP is unavailable', async () => {
    vi.mocked(mockMCP.getYieldOpportunities).mockRejectedValue(new Error('MCP down'))
    vi.mocked(mockMCP.getCrossChainYields).mockRejectedValue(new Error('MCP down'))

    const strategies = await engine.evaluate(mockIntent)
    expect(strategies.length).toBeGreaterThan(0)
  })

  it('filters strategies below intent targetAPY when alternatives exist', async () => {
    const flowYields: YieldOpportunity[] = [
      { protocol: 'LowYield', asset: 'USDC', apy: 1.0, chain: 'flow' },
      { protocol: 'GoodYield', asset: 'USDC', apy: 8.0, chain: 'flow' },
    ]
    vi.mocked(mockMCP.getYieldOpportunities).mockResolvedValue(flowYields)
    vi.mocked(mockMCP.getCrossChainYields).mockResolvedValue([])

    const strategies = await engine.evaluate({ ...mockIntent, targetAPY: 4.0 })
    // Only strategies >= 4.0% APY should be returned when viable ones exist
    const belowThreshold = strategies.filter((s) => s.expectedAPY < 4.0)
    expect(belowThreshold).toHaveLength(0)
  })
})
