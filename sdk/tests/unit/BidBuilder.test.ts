import { describe, it, expect } from 'vitest'
import { toUFix64, buildBidArgs, strategyToBidArgs } from '../../src/BidBuilder'
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
    const args = strategyToBidArgs('42', mockStrategy, 7)
    expect(args.offeredAPY).toBe('8.00000000')
    expect(args.intentId).toBe('42')
    expect(args.agentTokenId).toBe('7')
  })

  it('encodes batch as hex string', () => {
    const args = strategyToBidArgs('1', mockStrategy, 1)
    expect(args.encodedBatch).toBe('deadbeef')
  })
})

describe('buildBidArgs', () => {
  it('returns an array of 4 FCL args', () => {
    const args = buildBidArgs({
      intentId: '1',
      offeredAPY: '8.00000000',
      agentTokenId: '5',
      encodedBatch: 'deadbeef',
    })
    expect(args).toHaveLength(4)
  })
})
