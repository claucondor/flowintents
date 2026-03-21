/**
 * BidBuilder — constructs FCL transaction arguments for submitBid.cdc.
 *
 * IMPORTANT: UFix64 in FCL MUST be a string with exactly 8 decimal places.
 * e.g.  8.0  →  "8.00000000"
 *       4.1  →  "4.10000000"
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import type { Strategy } from './types/Strategy'

export interface BidArgs {
  /** The intent ID (UInt64 → string) */
  intentId: string
  /** Offered APY as UFix64 string, e.g. "8.00000000" */
  offeredAPY: string
  /** Solver's ERC-8004 agent token ID (UInt64 → string) */
  agentTokenId: string
  /** ABI-encoded BatchStep[] as hex string (without 0x) */
  encodedBatch: string
}

/**
 * Formats a number or numeric string to UFix64 (exactly 8 decimal places).
 *
 * Known FCL bug: passing a number directly is deprecated and breaks.
 * Always pass as string with 8 decimals.
 */
export function toUFix64(value: number | string): string {
  const num = typeof value === 'string' ? parseFloat(value) : value
  if (!isFinite(num) || num < 0) {
    throw new Error(`toUFix64: invalid value "${value}"`)
  }
  return num.toFixed(8)
}

/**
 * Builds the FCL transaction argument array for submitBid.cdc.
 *
 * Expected Cadence transaction signature:
 *   transaction(
 *     intentId: UInt64,
 *     offeredAPY: UFix64,
 *     agentTokenId: UInt64,
 *     encodedBatch: String
 *   )
 */
export function buildBidArgs(args: BidArgs): ReturnType<typeof fcl.arg>[] {
  return [
    fcl.arg(args.intentId, t.UInt64),
    fcl.arg(toUFix64(args.offeredAPY), t.UFix64),
    fcl.arg(args.agentTokenId, t.UInt64),
    fcl.arg(args.encodedBatch, t.String),
  ]
}

/**
 * Derives bid arguments from an Intent ID and a resolved Strategy.
 */
export function strategyToBidArgs(
  intentId: string,
  strategy: Strategy,
  agentTokenId: number,
): BidArgs {
  const encodedBatch = Buffer.from(strategy.encodedBatch).toString('hex')
  return {
    intentId,
    offeredAPY: toUFix64(strategy.expectedAPY),
    agentTokenId: agentTokenId.toString(),
    encodedBatch,
  }
}
