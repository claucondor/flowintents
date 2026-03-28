/**
 * solver-lib.ts — Shared logic for FlowIntents solver bots.
 *
 * Handles:
 *   - FCL configuration + private-key authorization
 *   - Polling open intents from REST API
 *   - Checking existing bids by solver address
 *   - Submitting bids via FCL
 *   - Watching for WinnerSelected events
 *   - Executing won intents via FCL
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import { ec as EC } from 'elliptic'
import { SHA3 } from 'sha3'
import type { InteractionAccount } from '@onflow/typedefs'
import {
  encodeANKRStakeStrategy,
  encodeWrapAndSwapStrategy,
  flowToAtto,
} from './src/strategies'
import { TOKENS } from './src/types'

// ── Constants ──────────────────────────────────────────────────────────────────

export const DEPLOYER = '0xc65395858a38d8ff'
export const ACCESS_NODE = 'https://rest-mainnet.onflow.org'
export const POLL_INTERVAL_MS = 15_000
export const EVENT_LOOKBACK_BLOCKS = 60  // ~1 min on Flow mainnet

// ── Types ──────────────────────────────────────────────────────────────────────

export interface Intent {
  id: number
  intentOwner: string
  principalAmount: number
  intentType: 'Yield' | 'Swap' | 'BridgeYield'
  targetAPY: number
  minAmountOut?: number
  maxFeeBPS?: number
  durationDays: number
  expiryBlock: number
  status: 'Open' | 'BidSelected' | 'Active' | 'Completed' | 'Cancelled' | 'Expired'
  principalSide: 'cadence' | 'evm'
  gasEscrowBalance: number
  executionDeadlineBlock: number
  winningBidID?: number
  recipientEVMAddress?: string
}

export interface SolverProfile {
  name: string
  address: string
  privateKey: string
  evmAddress: string
  color: string
  // Bid strategy knobs
  yieldAPYBonus: number        // add to targetAPY (e.g. +1.5 or -0.5)
  swapAmountOutMultiplier: number  // multiply minAmountOut (e.g. 1.02 or 1.0)
  maxGasBid: number            // FLOW (e.g. 0.001 or 0.003)
}

// ── Logging ────────────────────────────────────────────────────────────────────

function ts() {
  return new Date().toISOString().slice(11, 23)
}

export function log(color: string, botName: string, msg: string) {
  // ANSI colors: blue=34, green=32, yellow=33, red=31, cyan=36, magenta=35
  const codes: Record<string, number> = {
    blue: 34, green: 32, yellow: 33, red: 31, cyan: 36, magenta: 35, white: 37, gray: 90,
  }
  const code = codes[color] ?? 37
  console.log(`\x1b[90m${ts()}\x1b[0m \x1b[${code}m[${botName}]\x1b[0m ${msg}`)
}

// ── FCL setup ─────────────────────────────────────────────────────────────────

export function configureFCL() {
  fcl.config({
    'accessNode.api': ACCESS_NODE,
    'flow.network': 'mainnet',
    '0xFungibleToken': '0xf233dcee88fe0abe',
    '0xFlowToken': '0x1654653399040a61',
    '0xIntentMarketplaceV0_3': DEPLOYER,
    '0xBidManagerV0_3': DEPLOYER,
    '0xIntentExecutorV0_3': DEPLOYER,
  })
}

// ── Private key signing ───────────────────────────────────────────────────────

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

// ── REST helpers (no FCL) ─────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function parseCDC(value: any): any {
  if (value === null || value === undefined) return null
  const { type, value: v } = value
  switch (type) {
    case 'Optional': return v === null ? null : parseCDC(v)
    case 'UInt8': case 'UInt16': case 'UInt32': case 'UInt64':
    case 'Int8': case 'Int16': case 'Int32': case 'Int64':
    case 'Int': case 'UInt': return parseInt(v, 10)
    case 'UFix64': case 'Fix64': return parseFloat(v)
    case 'Bool': return v === true || v === 'true'
    case 'String': case 'Address': return v as string
    case 'Array': return (v as unknown[]).map(parseCDC)
    case 'Dictionary':
      return Object.fromEntries((v as { key: unknown; value: unknown }[]).map(
        (e) => [parseCDC(e.key), parseCDC(e.value)]
      ))
    case 'Struct': case 'Resource': case 'Event': case 'Enum': {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result: Record<string, any> = {}
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      for (const field of ((v as any).fields ?? [])) {
        result[field.name] = parseCDC(field.value)
      }
      return result
    }
    default: return v
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function execScript(code: string, args: any[] = []): Promise<any> {
  const res = await fetch(`${ACCESS_NODE}/v1/scripts`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      script: Buffer.from(code).toString('base64'),
      arguments: args.map((a) => Buffer.from(JSON.stringify(a)).toString('base64')),
    }),
  })
  if (!res.ok) throw new Error(`Script failed (${res.status}): ${await res.text()}`)
  const encoded = await res.text()
  let decoded: string
  try {
    decoded = Buffer.from(encoded.replace(/^"|"$/g, '').replace(/\\n/g, '').trim(), 'base64').toString()
  } catch {
    decoded = Buffer.from(JSON.parse(encoded), 'base64').toString()
  }
  return parseCDC(JSON.parse(decoded))
}

// ── Chain reads ───────────────────────────────────────────────────────────────

const OPEN_INTENTS_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}
access(all) fun main(): [UInt64] {
  return IntentMarketplaceV0_3.getOpenIntents()
}
`

const GET_INTENT_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}

access(all) struct IntentView {
  access(all) let id: UInt64
  access(all) let intentOwner: Address
  access(all) let principalAmount: UFix64
  access(all) let intentType: UInt8
  access(all) let targetAPY: UFix64
  access(all) let minAmountOut: UFix64?
  access(all) let maxFeeBPS: UInt64?
  access(all) let durationDays: UInt64
  access(all) let expiryBlock: UInt64
  access(all) let status: UInt8
  access(all) let winningBidID: UInt64?
  access(all) let createdAt: UFix64
  access(all) let principalSide: UInt8
  access(all) let gasEscrowBalance: UFix64
  access(all) let executionDeadlineBlock: UInt64
  access(all) let recipientEVMAddress: String?

  init(id: UInt64, intentOwner: Address, principalAmount: UFix64, intentType: UInt8,
       targetAPY: UFix64, minAmountOut: UFix64?, maxFeeBPS: UInt64?,
       durationDays: UInt64, expiryBlock: UInt64, status: UInt8,
       winningBidID: UInt64?, createdAt: UFix64, principalSide: UInt8,
       gasEscrowBalance: UFix64, executionDeadlineBlock: UInt64, recipientEVMAddress: String?) {
    self.id = id; self.intentOwner = intentOwner; self.principalAmount = principalAmount
    self.intentType = intentType; self.targetAPY = targetAPY; self.minAmountOut = minAmountOut
    self.maxFeeBPS = maxFeeBPS; self.durationDays = durationDays; self.expiryBlock = expiryBlock
    self.status = status; self.winningBidID = winningBidID; self.createdAt = createdAt
    self.principalSide = principalSide; self.gasEscrowBalance = gasEscrowBalance
    self.executionDeadlineBlock = executionDeadlineBlock; self.recipientEVMAddress = recipientEVMAddress
  }
}

access(all) fun main(intentID: UInt64): IntentView? {
  if let intent = IntentMarketplaceV0_3.getIntent(id: intentID) {
    return IntentView(
      id: intent.id, intentOwner: intent.intentOwner,
      principalAmount: intent.principalAmount, intentType: intent.intentType.rawValue,
      targetAPY: intent.targetAPY, minAmountOut: intent.minAmountOut,
      maxFeeBPS: intent.maxFeeBPS, durationDays: intent.durationDays,
      expiryBlock: intent.expiryBlock, status: intent.status.rawValue,
      winningBidID: intent.winningBidID, createdAt: intent.createdAt,
      principalSide: intent.principalSide.rawValue,
      gasEscrowBalance: intent.getGasEscrowBalance(),
      executionDeadlineBlock: intent.executionDeadlineBlock,
      recipientEVMAddress: intent.recipientEVMAddress
    )
  }
  return nil
}
`

const BIDS_BY_SOLVER_SCRIPT = `
import BidManagerV0_3 from ${DEPLOYER}
access(all) fun main(solver: Address): [UInt64] {
  return BidManagerV0_3.getBidsBySolver(solver)
}
`

const BIDS_FOR_INTENT_SCRIPT = `
import BidManagerV0_3 from ${DEPLOYER}
access(all) fun main(intentID: UInt64): [UInt64] {
  return BidManagerV0_3.getBidsForIntent(intentID: intentID)
}
`

const INTENT_TYPE_MAP = ['Yield', 'Swap', 'BridgeYield'] as const
const INTENT_STATUS_MAP = ['Open', 'BidSelected', 'Active', 'Completed', 'Cancelled', 'Expired'] as const

export async function getOpenIntentIds(): Promise<number[]> {
  const result = await execScript(OPEN_INTENTS_SCRIPT, [])
  return Array.isArray(result) ? result : []
}

export async function getIntent(id: number): Promise<Intent | null> {
  const r = await execScript(GET_INTENT_SCRIPT, [{ type: 'UInt64', value: id.toString() }])
  if (!r) return null
  return {
    id: r.id ?? id,
    intentOwner: r.intentOwner ?? '',
    principalAmount: r.principalAmount ?? 0,
    intentType: INTENT_TYPE_MAP[r.intentType ?? 0] ?? 'Yield',
    targetAPY: r.targetAPY ?? 0,
    minAmountOut: r.minAmountOut ?? undefined,
    maxFeeBPS: r.maxFeeBPS ?? undefined,
    durationDays: r.durationDays ?? 0,
    expiryBlock: r.expiryBlock ?? 0,
    status: INTENT_STATUS_MAP[r.status ?? 0] ?? 'Open',
    principalSide: r.principalSide === 1 ? 'evm' : 'cadence',
    gasEscrowBalance: r.gasEscrowBalance ?? 0,
    executionDeadlineBlock: r.executionDeadlineBlock ?? 0,
    winningBidID: r.winningBidID ?? undefined,
    recipientEVMAddress: r.recipientEVMAddress ?? undefined,
  }
}

export async function getBidsBySolver(solverAddress: string): Promise<number[]> {
  const result = await execScript(BIDS_BY_SOLVER_SCRIPT, [{ type: 'Address', value: solverAddress }])
  return Array.isArray(result) ? result : []
}

export async function getBidsForIntent(intentID: number): Promise<number[]> {
  const result = await execScript(BIDS_FOR_INTENT_SCRIPT, [{ type: 'UInt64', value: intentID.toString() }])
  return Array.isArray(result) ? result : []
}

export async function getCurrentBlockHeight(): Promise<number> {
  const res = await fetch(`${ACCESS_NODE}/v1/blocks?height=sealed`)
  if (!res.ok) throw new Error(`Failed to get block: ${res.status}`)
  const data = await res.json()
  return parseInt(data[0].header.height, 10)
}

// ── Event polling ─────────────────────────────────────────────────────────────

export interface WinnerSelectedEvent {
  intentID: number
  winningBidID: number
  solverAddress: string
  blockHeight: number
  transactionId: string
}

async function queryEvents(
  eventType: string,
  startBlock: number,
  endBlock: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any[]> {
  const CHUNK = 250
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const all: any[] = []
  for (let start = startBlock; start <= endBlock; start += CHUNK) {
    const end = Math.min(start + CHUNK - 1, endBlock)
    try {
      const res = await fetch(
        `${ACCESS_NODE}/v1/events?type=${encodeURIComponent(eventType)}&start_height=${start}&end_height=${end}`
      )
      if (!res.ok) continue
      const data = await res.json()
      if (Array.isArray(data)) {
        for (const blockResult of data) {
          if (Array.isArray(blockResult.events)) all.push(...blockResult.events)
        }
      }
    } catch {
      // skip chunk errors
    }
  }
  return all
}

export async function getWinnerSelectedEvents(
  startBlock: number,
  endBlock: number,
): Promise<WinnerSelectedEvent[]> {
  const raw = await queryEvents(
    `A.${DEPLOYER.slice(2)}.BidManagerV0_3.WinnerSelected`,
    startBlock,
    endBlock,
  )
  return raw.map((e) => {
    try {
      const payloadStr = Buffer.from(e.payload, 'base64').toString()
      const parsed = JSON.parse(payloadStr)
      const data = parseCDC(parsed) ?? {}
      return {
        intentID: data.intentID ?? 0,
        winningBidID: data.winningBidID ?? 0,
        solverAddress: data.solverAddress ?? '',
        blockHeight: parseInt(e.block_height, 10),
        transactionId: e.transaction_id,
      } as WinnerSelectedEvent
    } catch {
      return null
    }
  }).filter(Boolean) as WinnerSelectedEvent[]
}

// ── FCL Cadence transactions ──────────────────────────────────────────────────

const SUBMIT_BID_CDC = `
import BidManagerV0_3 from ${DEPLOYER}

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
    let bidID = BidManagerV0_3.submitBid(
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
    log("Bid ".concat(bidID.toString()).concat(" submitted"))
  }
}
`

const EXECUTE_INTENT_CDC = `
import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentExecutorV0_3 from ${DEPLOYER}

transaction(intentID: UInt64, recipientEVMAddress: String?) {
  let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
  let solverAddress: Address
  let solverReceiver: &{FungibleToken.Receiver}

  prepare(signer: auth(Storage, BorrowValue) &Account) {
    self.solverAddress = signer.address
    self.coa = signer.storage
      .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
      ?? panic("Solver must have a COA at /storage/evm")
    self.solverReceiver = signer.storage
      .borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
      ?? panic("Cannot borrow FlowToken vault")
  }

  execute {
    IntentExecutorV0_3.executeIntentV2(
      intentID: intentID,
      solverAddress: self.solverAddress,
      coa: self.coa,
      solverFlowReceiver: self.solverReceiver,
      recipientEVMAddress: recipientEVMAddress
    )
    log("Intent ".concat(intentID.toString()).concat(" executed"))
  }
}
`

function toUFix64(v: number): string {
  return v.toFixed(8)
}

function hexToUint8Array(hex: string): number[] {
  const stripped = hex.startsWith('0x') ? hex.slice(2) : hex
  const bytes: number[] = []
  for (let i = 0; i < stripped.length; i += 2) {
    bytes.push(parseInt(stripped.slice(i, i + 2), 16))
  }
  return bytes
}

export interface BidSubmitParams {
  intentID: number
  offeredAPY?: number
  offeredAmountOut?: number
  maxGasBid: number
  strategy: string
  encodedBatch: string
}

export async function submitBidTx(
  params: BidSubmitParams,
  address: string,
  privateKey: string,
): Promise<string> {
  const authz = buildAuthorization(address, privateKey)
  const encodedBatchBytes = hexToUint8Array(params.encodedBatch)

  const txId: string = await fcl.mutate({
    cadence: SUBMIT_BID_CDC,
    args: (arg: typeof fcl.arg, _t: typeof t) => [
      arg(params.intentID.toString(), _t.UInt64),
      arg(params.offeredAPY != null ? toUFix64(params.offeredAPY) : null, _t.Optional(_t.UFix64)),
      arg(params.offeredAmountOut != null ? toUFix64(params.offeredAmountOut) : null, _t.Optional(_t.UFix64)),
      arg(null, _t.Optional(_t.UInt64)),   // estimatedFeeBPS
      arg(null, _t.Optional(_t.String)),   // targetChain
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

export async function executeIntentTx(
  intentID: number,
  recipientEVMAddress: string | null,
  address: string,
  privateKey: string,
): Promise<string> {
  const authz = buildAuthorization(address, privateKey)

  const txId: string = await fcl.mutate({
    cadence: EXECUTE_INTENT_CDC,
    args: (arg: typeof fcl.arg, _t: typeof t) => [
      arg(intentID.toString(), _t.UInt64),
      arg(recipientEVMAddress, _t.Optional(_t.String)),
    ],
    proposer: authz,
    payer: authz,
    authorizations: [authz],
    limit: 9999,
  })

  await fcl.tx(txId).onceSealed()
  return txId
}

// ── Strategy builders ─────────────────────────────────────────────────────────

export function buildYieldBatch(principalAmount: number, evmAddress: string): string {
  return encodeANKRStakeStrategy(principalAmount, evmAddress)
}

export function buildSwapBatch(
  principalAmount: number,
  minAmountOut: number,
  evmAddress: string,
): string {
  // Wrap all FLOW and swap for stgUSDC
  const minOut = BigInt(Math.floor(minAmountOut))
  return encodeWrapAndSwapStrategy(
    principalAmount,
    principalAmount,
    TOKENS.stgUSDC,
    evmAddress,
    minOut,
  )
}

// ── Core solver loop ──────────────────────────────────────────────────────────

export async function runSolverLoop(profile: SolverProfile) {
  const { name, address, privateKey, evmAddress, color } = profile

  log(color, name, `Starting solver bot — address: ${address}`)
  log(color, name, `Strategy: ANKR (yield) + PunchSwap (swap) | maxGasBid: ${profile.maxGasBid} FLOW`)

  // Track which intent IDs we've already bid on this run (local cache)
  const biddedIntents = new Set<number>()
  // Track last polled block for event watching
  let lastEventBlock = 0

  // Seed with existing bids on-chain
  try {
    const existingBidIds = await getBidsBySolver(address)
    log(color, name, `Found ${existingBidIds.length} existing bid(s) on-chain`)
    // We can't easily map bid IDs → intent IDs without fetching each bid.
    // To keep it simple, we just let the duplicate-bid check below handle it.
  } catch (err) {
    log('red', name, `Warning: failed to load existing bids: ${err}`)
  }

  async function tick() {
    try {
      // 1. Get current block
      const currentBlock = await getCurrentBlockHeight()
      if (lastEventBlock === 0) lastEventBlock = currentBlock - 1

      // 2. Get open intents
      const openIds = await getOpenIntentIds()
      log(color, name, `Poll — block ${currentBlock} — ${openIds.length} open intent(s)`)

      // 3. For each open intent, bid if we haven't yet
      for (const intentId of openIds) {
        if (biddedIntents.has(intentId)) continue

        let intent: Intent | null = null
        try {
          intent = await getIntent(intentId)
        } catch (err) {
          log('red', name, `  Failed to fetch intent #${intentId}: ${err}`)
          continue
        }
        if (!intent || intent.status !== 'Open') continue

        // Check existing bids for this intent to avoid duplicating
        try {
          const existingBids = await getBidsForIntent(intentId)
          // Fetch each bid to see if we already submitted one
          // For speed during demo, skip this check (the contract will reject duplicate bids anyway)
          void existingBids
        } catch {
          // ignore
        }

        try {
          log(color, name, `  Bidding on intent #${intentId} (${intent.intentType} — ${intent.principalAmount} FLOW)`)

          if (intent.intentType === 'Yield') {
            const offeredAPY = Math.max(0.01, intent.targetAPY + profile.yieldAPYBonus)
            const batch = buildYieldBatch(intent.principalAmount, evmAddress)
            const txId = await submitBidTx({
              intentID: intentId,
              offeredAPY,
              maxGasBid: profile.maxGasBid,
              strategy: 'ankr-stake',
              encodedBatch: batch,
            }, address, privateKey)
            biddedIntents.add(intentId)
            log('green', name, `  Bid submitted — tx: ${txId.slice(0, 16)}… offeredAPY: ${offeredAPY.toFixed(2)}%`)
          } else if (intent.intentType === 'Swap') {
            const minOut = intent.minAmountOut ?? 0
            const offeredAmountOut = minOut * profile.swapAmountOutMultiplier
            const batch = buildSwapBatch(intent.principalAmount, Math.floor(offeredAmountOut), evmAddress)
            const txId = await submitBidTx({
              intentID: intentId,
              offeredAmountOut,
              maxGasBid: profile.maxGasBid,
              strategy: 'punchswap-v2',
              encodedBatch: batch,
            }, address, privateKey)
            biddedIntents.add(intentId)
            log('green', name, `  Bid submitted — tx: ${txId.slice(0, 16)}… offeredOut: ${offeredAmountOut.toFixed(4)}`)
          } else {
            log('gray', name, `  Skipping intent #${intentId} (unsupported type: ${intent.intentType})`)
          }
        } catch (err) {
          log('red', name, `  Bid failed for intent #${intentId}: ${(err as Error).message ?? err}`)
          // If error is "already bid", mark as done
          if (String(err).includes('already') || String(err).includes('duplicate')) {
            biddedIntents.add(intentId)
          }
        }
      }

      // 4. Check WinnerSelected events — did we win?
      try {
        const winners = await getWinnerSelectedEvents(lastEventBlock + 1, currentBlock)
        lastEventBlock = currentBlock
        for (const w of winners) {
          const addrNorm = (s: string) => s.toLowerCase().replace('0x', '')
          if (addrNorm(w.solverAddress) !== addrNorm(address)) continue

          log('yellow', name, `  WON intent #${w.intentID}! Bid #${w.winningBidID} — executing...`)
          try {
            const intent = await getIntent(w.intentID)
            const recipient = intent?.recipientEVMAddress ?? null
            const txId = await executeIntentTx(w.intentID, recipient, address, privateKey)
            log('green', name, `  EXECUTED intent #${w.intentID} — tx: ${txId.slice(0, 16)}… Gas escrow claimed!`)
          } catch (execErr) {
            log('red', name, `  Execution failed for intent #${w.intentID}: ${execErr}`)
          }
        }
      } catch (evtErr) {
        log('gray', name, `  Event poll failed (non-fatal): ${evtErr}`)
      }
    } catch (err) {
      log('red', name, `Poll error: ${err}`)
    }
  }

  // Initial tick
  await tick()

  // Poll every POLL_INTERVAL_MS
  setInterval(tick, POLL_INTERVAL_MS)
}
