/**
 * BidBuilder — constructs FCL transaction arguments for submitBid.cdc.
 *
 * IMPORTANT: UFix64 in FCL MUST be a string with exactly 8 decimal places.
 * e.g.  8.0  →  "8.00000000"
 *       4.1  →  "4.10000000"
 *
 * Updated Cadence submitBid signature (Sprint 2):
 *   transaction(
 *     intentID: UInt64,
 *     offeredAPY: UFix64?,          // Yield / BridgeYield intents
 *     offeredAmountOut: UFix64?,    // Swap intents
 *     encodedBatch: [UInt8],        // ABI-encoded BatchStep[] as byte array
 *     solverEVMAddress: String,
 *     targetChain: String?,
 *     estimatedFeeBPS: UInt64?
 *   )
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import type { Strategy } from './types/Strategy'

export interface BidArgs {
  /** The intent ID (UInt64 → string) */
  intentId: string
  /** Offered APY as UFix64 string (for Yield/BridgeYield), e.g. "8.00000000". Null for Swap. */
  offeredAPY: string | null
  /** Offered amount out as UFix64 string (for Swap). Null for Yield. */
  offeredAmountOut: string | null
  /** ABI-encoded BatchStep[] as array of byte values (UInt8[]) */
  encodedBatch: number[]
  /** Solver's EVM address (0x-prefixed) */
  solverEVMAddress: string
  /** Target chain identifier (e.g. "ethereum", "base"), null for Flow-native */
  targetChain: string | null
  /** Estimated fee in basis points (UInt64), null if not applicable */
  estimatedFeeBPS: string | null
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
 * Converts a Uint8Array / Buffer (ABI-encoded batch) into a number[] for Cadence [UInt8].
 */
export function encodedBatchToUInt8Array(batch: Uint8Array): number[] {
  return Array.from(batch)
}

/**
 * Builds the FCL transaction argument array for submitBid.cdc.
 *
 * Maps the BidArgs to the updated Cadence transaction signature with:
 *   - Optional UFix64 fields (offeredAPY, offeredAmountOut) using t.Optional(t.UFix64)
 *   - encodedBatch as [UInt8] (array of UInt8)
 *   - solverEVMAddress as String
 *   - Optional targetChain and estimatedFeeBPS
 */
export function buildBidArgs(args: BidArgs): ReturnType<typeof fcl.arg>[] {
  return [
    fcl.arg(args.intentId, t.UInt64),
    fcl.arg(
      args.offeredAPY !== null ? toUFix64(args.offeredAPY) : null,
      t.Optional(t.UFix64),
    ),
    fcl.arg(
      args.offeredAmountOut !== null ? toUFix64(args.offeredAmountOut) : null,
      t.Optional(t.UFix64),
    ),
    fcl.arg(
      args.encodedBatch.map((b) => b.toString()),
      t.Array(t.UInt8),
    ),
    fcl.arg(args.solverEVMAddress, t.String),
    fcl.arg(args.targetChain ?? null, t.Optional(t.String)),
    fcl.arg(args.estimatedFeeBPS ?? null, t.Optional(t.UInt64)),
  ]
}

/**
 * Derives bid arguments from an Intent ID and a resolved Strategy.
 * Assumes a Yield-type intent (sets offeredAPY, leaves offeredAmountOut null).
 */
export function strategyToBidArgs(
  intentId: string,
  strategy: Strategy,
  agentTokenId: number,
  solverEVMAddress = '0x0000000000000000000000000000000000000000',
): BidArgs {
  // agentTokenId kept for backwards compatibility but not sent in new signature
  void agentTokenId

  const encodedBatch = encodedBatchToUInt8Array(strategy.encodedBatch)

  return {
    intentId,
    offeredAPY: toUFix64(strategy.expectedAPY),
    offeredAmountOut: null,
    encodedBatch,
    solverEVMAddress,
    targetChain: strategy.chain !== 'flow' ? strategy.chain : null,
    estimatedFeeBPS: null,
  }
}
