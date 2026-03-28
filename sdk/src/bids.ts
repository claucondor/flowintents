/**
 * bids.ts — Submit and read bids via BidManagerV0_3.
 *
 * Submitting a bid requires a Cadence private key (signs the submitBidV0_3 transaction).
 * Reading bids is public (FCL scripts).
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import { ec as EC } from 'elliptic'
import { SHA3 } from 'sha3'
import type { InteractionAccount } from '@onflow/typedefs'
import type { Bid, BidParams } from './types'

// ─────────────────────────────────────────────
// Cadence private key signing
// ─────────────────────────────────────────────

const ec = new EC('p256')

function hashMsg(msg: string): Buffer {
  const sha = new SHA3(256)
  sha.update(Buffer.from(msg, 'hex'))
  return Buffer.from(sha.digest())
}

function signWithKey(privateKey: string, msg: string): string {
  const key = ec.keyFromPrivate(Buffer.from(privateKey, 'hex'))
  const sig = key.sign(hashMsg(msg))
  const n = 32
  const r = sig.r.toArrayLike(Buffer, 'be', n)
  const s = sig.s.toArrayLike(Buffer, 'be', n)
  return Buffer.concat([r, s]).toString('hex')
}

/**
 * Build a FCL authorization function for a Cadence account + raw private key.
 * Signing algorithm: ECDSA P-256 + SHA3-256 (Flow's default).
 */
export function buildAuthorization(
  address: string,
  privateKey: string,
  keyIndex = 0,
): (acct: InteractionAccount) => InteractionAccount {
  return (acct: InteractionAccount): InteractionAccount => ({
    ...acct,
    tempId: `${address}-${keyIndex}`,
    addr: fcl.withPrefix(address),
    keyId: keyIndex,
    sequenceNum: acct.sequenceNum ?? null,
    signature: acct.signature ?? null,
    resolve: null,
    signingFunction: (signable: { message: string }) => ({
      addr: fcl.withPrefix(address),
      keyId: keyIndex,
      signature: signWithKey(privateKey, signable.message),
    }),
  })
}

// ─────────────────────────────────────────────
// Cadence transactions / scripts
// ─────────────────────────────────────────────

/**
 * submitBidV0_3.cdc — inline version that calls BidManagerV0_3.submitBid().
 * Parameters match the on-chain transaction exactly.
 */
const SUBMIT_BID_CDC = (cadenceAddress: string) => `
import BidManagerV0_3 from 0x${cadenceAddress.replace(/^0x/, '')}

transaction(
  intentID: UInt64,
  offeredAPY: UFix64?,
  offeredAmountOut: UFix64?,
  estimatedFeeBPS: UInt64?,
  targetChain: String?,
  maxGasBid: UFix64,
  strategy: String,
  encodedBatch: [UInt8]
) {
  let solverAddress: Address

  prepare(signer: auth(Storage) &Account) {
    self.solverAddress = signer.address
  }

  execute {
    BidManagerV0_3.submitBid(
      intentID: intentID,
      solverAddress: self.solverAddress,
      offeredAPY: offeredAPY,
      offeredAmountOut: offeredAmountOut,
      estimatedFeeBPS: estimatedFeeBPS,
      targetChain: targetChain,
      maxGasBid: maxGasBid,
      strategy: strategy,
      encodedBatch: encodedBatch
    )
  }
}
`

/**
 * Script: get a single bid by ID.
 */
const GET_BID_SCRIPT = (cadenceAddress: string) => `
import BidManagerV0_3 from 0x${cadenceAddress.replace(/^0x/, '')}

access(all) struct BidView {
  access(all) let id: UInt64
  access(all) let intentID: UInt64
  access(all) let solverAddress: String
  access(all) let solverEVMAddress: String
  access(all) let offeredAPY: UFix64?
  access(all) let offeredAmountOut: UFix64?
  access(all) let estimatedFeeBPS: UInt64?
  access(all) let targetChain: String?
  access(all) let maxGasBid: UFix64
  access(all) let strategy: String
  access(all) let encodedBatch: [UInt8]
  access(all) let submittedAt: UFix64
  access(all) let score: UFix64

  init(
    id: UInt64, intentID: UInt64,
    solverAddress: String, solverEVMAddress: String,
    offeredAPY: UFix64?, offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?, targetChain: String?,
    maxGasBid: UFix64, strategy: String,
    encodedBatch: [UInt8], submittedAt: UFix64, score: UFix64
  ) {
    self.id = id; self.intentID = intentID
    self.solverAddress = solverAddress; self.solverEVMAddress = solverEVMAddress
    self.offeredAPY = offeredAPY; self.offeredAmountOut = offeredAmountOut
    self.estimatedFeeBPS = estimatedFeeBPS; self.targetChain = targetChain
    self.maxGasBid = maxGasBid; self.strategy = strategy
    self.encodedBatch = encodedBatch; self.submittedAt = submittedAt; self.score = score
  }
}

access(all) fun main(bidID: UInt64): BidView? {
  let bid = BidManagerV0_3.getBid(bidID: bidID)
  if bid == nil { return nil }
  let b = bid!
  return BidView(
    id: b.id, intentID: b.intentID,
    solverAddress: b.solverAddress.toString(),
    solverEVMAddress: b.solverEVMAddress,
    offeredAPY: b.offeredAPY, offeredAmountOut: b.offeredAmountOut,
    estimatedFeeBPS: b.estimatedFeeBPS, targetChain: b.targetChain,
    maxGasBid: b.maxGasBid, strategy: b.strategy,
    encodedBatch: b.encodedBatch, submittedAt: b.submittedAt, score: b.score
  )
}
`

/**
 * Script: get the winning bid for an intent.
 */
const GET_WINNING_BID_SCRIPT = (cadenceAddress: string) => `
import BidManagerV0_3 from 0x${cadenceAddress.replace(/^0x/, '')}

access(all) struct BidView {
  access(all) let id: UInt64
  access(all) let intentID: UInt64
  access(all) let solverAddress: String
  access(all) let solverEVMAddress: String
  access(all) let offeredAPY: UFix64?
  access(all) let offeredAmountOut: UFix64?
  access(all) let estimatedFeeBPS: UInt64?
  access(all) let targetChain: String?
  access(all) let maxGasBid: UFix64
  access(all) let strategy: String
  access(all) let encodedBatch: [UInt8]
  access(all) let submittedAt: UFix64
  access(all) let score: UFix64

  init(
    id: UInt64, intentID: UInt64,
    solverAddress: String, solverEVMAddress: String,
    offeredAPY: UFix64?, offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?, targetChain: String?,
    maxGasBid: UFix64, strategy: String,
    encodedBatch: [UInt8], submittedAt: UFix64, score: UFix64
  ) {
    self.id = id; self.intentID = intentID
    self.solverAddress = solverAddress; self.solverEVMAddress = solverEVMAddress
    self.offeredAPY = offeredAPY; self.offeredAmountOut = offeredAmountOut
    self.estimatedFeeBPS = estimatedFeeBPS; self.targetChain = targetChain
    self.maxGasBid = maxGasBid; self.strategy = strategy
    self.encodedBatch = encodedBatch; self.submittedAt = submittedAt; self.score = score
  }
}

access(all) fun main(intentID: UInt64): BidView? {
  let bid = BidManagerV0_3.getWinningBid(intentID: intentID)
  if bid == nil { return nil }
  let b = bid!
  return BidView(
    id: b.id, intentID: b.intentID,
    solverAddress: b.solverAddress.toString(),
    solverEVMAddress: b.solverEVMAddress,
    offeredAPY: b.offeredAPY, offeredAmountOut: b.offeredAmountOut,
    estimatedFeeBPS: b.estimatedFeeBPS, targetChain: b.targetChain,
    maxGasBid: b.maxGasBid, strategy: b.strategy,
    encodedBatch: b.encodedBatch, submittedAt: b.submittedAt, score: b.score
  )
}
`

// ─────────────────────────────────────────────
// Raw Cadence response shapes
// ─────────────────────────────────────────────

interface RawBidView {
  id: string
  intentID: string
  solverAddress: string
  solverEVMAddress: string
  offeredAPY: string | null
  offeredAmountOut: string | null
  estimatedFeeBPS: string | null
  targetChain: string | null
  maxGasBid: string
  strategy: string
  encodedBatch: string[]  // FCL returns [UInt8] as string[]
  submittedAt: string
  score: string
}

// ─────────────────────────────────────────────
// Parsers
// ─────────────────────────────────────────────

/**
 * Converts the ABI-encoded batch from Cadence [UInt8] (returned as string[]) to a 0x hex string.
 */
export function uint8ArrayToHex(bytes: string[] | number[]): string {
  const byteValues = bytes.map((b) => parseInt(String(b), 10))
  return '0x' + Buffer.from(byteValues).toString('hex')
}

/**
 * Converts a 0x-prefixed hex string (encodedBatch) to a number[] for Cadence [UInt8].
 */
export function hexToUint8Array(hex: string): number[] {
  const stripped = hex.startsWith('0x') ? hex.slice(2) : hex
  const bytes: number[] = []
  for (let i = 0; i < stripped.length; i += 2) {
    bytes.push(parseInt(stripped.slice(i, i + 2), 16))
  }
  return bytes
}

function parseBidView(raw: RawBidView): Bid {
  return {
    id: parseInt(raw.id, 10),
    intentID: parseInt(raw.intentID, 10),
    solverAddress: raw.solverAddress,
    solverEVMAddress: raw.solverEVMAddress,
    offeredAPY: raw.offeredAPY != null ? parseFloat(raw.offeredAPY) : undefined,
    offeredAmountOut: raw.offeredAmountOut != null ? parseFloat(raw.offeredAmountOut) : undefined,
    estimatedFeeBPS: raw.estimatedFeeBPS != null ? parseInt(raw.estimatedFeeBPS, 10) : undefined,
    targetChain: raw.targetChain ?? undefined,
    maxGasBid: parseFloat(raw.maxGasBid),
    strategy: raw.strategy,
    encodedBatch: uint8ArrayToHex(raw.encodedBatch),
    submittedAt: parseFloat(raw.submittedAt),
    score: parseFloat(raw.score),
  }
}

/**
 * Formats a JS number to UFix64 string with exactly 8 decimal places (FCL requirement).
 */
function toUFix64(value: number): string {
  return value.toFixed(8)
}

// ─────────────────────────────────────────────
// Public API — read
// ─────────────────────────────────────────────

/**
 * Fetches a single bid by ID. Returns null if not found.
 */
export async function getBid(bidID: number, cadenceAddress: string): Promise<Bid | null> {
  const script = GET_BID_SCRIPT(cadenceAddress)
  const result: RawBidView | null = await fcl.query({
    cadence: script,
    args: (arg: typeof fcl.arg, _t: typeof t) => [arg(bidID.toString(), _t.UInt64)],
  })
  return result ? parseBidView(result) : null
}

/**
 * Fetches the winning bid for an intent. Returns null if no winner selected yet.
 */
export async function getWinningBid(intentID: number, cadenceAddress: string): Promise<Bid | null> {
  const script = GET_WINNING_BID_SCRIPT(cadenceAddress)
  const result: RawBidView | null = await fcl.query({
    cadence: script,
    args: (arg: typeof fcl.arg, _t: typeof t) => [arg(intentID.toString(), _t.UInt64)],
  })
  return result ? parseBidView(result) : null
}

// ─────────────────────────────────────────────
// Public API — write (requires private key)
// ─────────────────────────────────────────────

/**
 * Submit a bid to BidManagerV0_3.
 *
 * @param params         Bid parameters.
 * @param cadenceAddress The Cadence contract deployer address.
 * @param flowAddress    The solver's Cadence account address (must be registered).
 * @param privateKey     The solver's Cadence private key (hex, no 0x prefix).
 * @param keyIndex       Key index to sign with (default: 0).
 * @returns              The sealed Cadence transaction ID.
 */
export async function submitBid(
  params: BidParams,
  cadenceAddress: string,
  flowAddress: string,
  privateKey: string,
  keyIndex = 0,
): Promise<string> {
  const authz = buildAuthorization(flowAddress, privateKey, keyIndex)
  const encodedBatchBytes = hexToUint8Array(params.encodedBatch)

  const txId: string = await fcl.mutate({
    cadence: SUBMIT_BID_CDC(cadenceAddress),
    args: (arg: typeof fcl.arg, _t: typeof t) => [
      arg(params.intentID.toString(), _t.UInt64),
      arg(
        params.offeredAPY != null ? toUFix64(params.offeredAPY) : null,
        _t.Optional(_t.UFix64),
      ),
      arg(
        params.offeredAmountOut != null ? toUFix64(params.offeredAmountOut) : null,
        _t.Optional(_t.UFix64),
      ),
      arg(
        params.estimatedFeeBPS != null ? params.estimatedFeeBPS.toString() : null,
        _t.Optional(_t.UInt64),
      ),
      arg(params.targetChain ?? null, _t.Optional(_t.String)),
      arg(toUFix64(params.maxGasBid), _t.UFix64),
      arg(params.strategy, _t.String),
      arg(encodedBatchBytes.map(String), _t.Array(_t.UInt8)),
    ],
    proposer: authz,
    payer: authz,
    authorizations: [authz],
    limit: 9999,
  })

  await fcl.tx(txId).onceSealed()
  return txId
}
