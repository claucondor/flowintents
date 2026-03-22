import { describe, it, expect } from 'vitest'
import { toUFix64, buildBidArgs, strategyToBidArgs, encodedBatchToUInt8Array } from '../../src/BidBuilder'
import type { Strategy } from '../../src/types/Strategy'

describe('toUFix64', () => {
  it('formats integer to 8 decimals', () => {
    expect(toUFix64(8)).toBe('8.00000000')
  })

  it('formats float to 8 decimals', () => {
    expect(toUFix64(4.1)).toBe('4.10000000')
  })

  it('formats string number to 8 decimals', () => {
    expect(toUFix64('12.5')).toBe('12.50000000')
  })

  it('formats zero correctly', () => {
    expect(toUFix64(0)).toBe('0.00000000')
  })

  it('throws on negative value', () => {
    expect(() => toUFix64(-1)).toThrow()
  })

  it('throws on NaN', () => {
    expect(() => toUFix64('not-a-number')).toThrow()
  })
})

describe('encodedBatchToUInt8Array', () => {
  it('converts Uint8Array to number[]', () => {
    const input = new Uint8Array([0xde, 0xad, 0xbe, 0xef])
    expect(encodedBatchToUInt8Array(input)).toEqual([222, 173, 190, 239])
  })
})

describe('strategyToBidArgs', () => {
  const mockStrategy: Strategy = {
    protocol: 'MORE Finance',
    chain: 'flow',
    expectedAPY: 8.0,
    confidence: 0.9,
    encodedBatch: new Uint8Array([0xde, 0xad, 0xbe, 0xef]),
    rationale: 'test strategy',
  }

  it('builds bid args with correct UFix64 APY', () => {
    const args = strategyToBidArgs('42', mockStrategy, 7, '0xSolverEVM')
    expect(args.offeredAPY).toBe('8.00000000')
    expect(args.intentId).toBe('42')
  })

  it('encodes batch as number[]', () => {
    const args = strategyToBidArgs('1', mockStrategy, 1, '0xSolverEVM')
    expect(args.encodedBatch).toEqual([0xde, 0xad, 0xbe, 0xef])
  })

  it('sets offeredAmountOut to null for yield strategy', () => {
    const args = strategyToBidArgs('1', mockStrategy, 1, '0xSolverEVM')
    expect(args.offeredAmountOut).toBeNull()
  })

  it('sets targetChain to null for flow strategy', () => {
    const args = strategyToBidArgs('1', mockStrategy, 1, '0xSolverEVM')
    expect(args.targetChain).toBeNull()
  })

  it('sets targetChain for cross-chain strategy', () => {
    const crossChainStrategy: Strategy = { ...mockStrategy, chain: 'ethereum' }
    const args = strategyToBidArgs('1', crossChainStrategy, 1, '0xSolverEVM')
    expect(args.targetChain).toBe('ethereum')
  })
})

describe('buildBidArgs', () => {
  it('returns an array of 7 FCL args matching updated submitBid signature', () => {
    const args = buildBidArgs({
      intentId: '1',
      offeredAPY: '8.00000000',
      offeredAmountOut: null,
      encodedBatch: [0xde, 0xad, 0xbe, 0xef],
      solverEVMAddress: '0xSolverEVM',
      targetChain: null,
      estimatedFeeBPS: null,
    })
    expect(args).toHaveLength(7)
  })
})
