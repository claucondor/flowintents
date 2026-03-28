/**
 * intents.ts — Read intents from the Cadence IntentMarketplaceV0_3 contract.
 *
 * Uses FCL scripts (read-only, no signing required).
 */

import * as fcl from '@onflow/fcl'
import type { Intent, IntentType, IntentStatus, PrincipalSide } from './types'

// ─────────────────────────────────────────────
// Cadence scripts (inline)
// ─────────────────────────────────────────────

/**
 * Returns all intent IDs with status == Open.
 * Returns: [UInt64]
 */
const GET_OPEN_INTENT_IDS_SCRIPT = `
import IntentMarketplaceV0_3 from 0xCADENCE_ADDRESS

access(all) fun main(): [UInt64] {
  return IntentMarketplaceV0_3.getOpenIntents()
}
`

/**
 * Returns a single intent by ID as a serialisable struct.
 * Returns: {fields...} or nil
 */
const GET_INTENT_SCRIPT = `
import IntentMarketplaceV0_3 from 0xCADENCE_ADDRESS

access(all) struct IntentView {
  access(all) let id: UInt64
  access(all) let intentOwner: String
  access(all) let principalAmount: UFix64
  access(all) let intentType: UInt8
  access(all) let targetAPY: UFix64
  access(all) let minAmountOut: UFix64?
  access(all) let maxFeeBPS: UInt64?
  access(all) let minAPY: UFix64?
  access(all) let durationDays: UInt64
  access(all) let expiryBlock: UInt64
  access(all) let status: UInt8
  access(all) let principalSide: UInt8
  access(all) let recipientEVMAddress: String?
  access(all) let winningBidID: UInt64?
  access(all) let createdAt: UFix64
  access(all) let executionDeadlineBlock: UInt64
  access(all) let gasEscrowBalance: UFix64

  init(
    id: UInt64,
    intentOwner: String,
    principalAmount: UFix64,
    intentType: UInt8,
    targetAPY: UFix64,
    minAmountOut: UFix64?,
    maxFeeBPS: UInt64?,
    minAPY: UFix64?,
    durationDays: UInt64,
    expiryBlock: UInt64,
    status: UInt8,
    principalSide: UInt8,
    recipientEVMAddress: String?,
    winningBidID: UInt64?,
    createdAt: UFix64,
    executionDeadlineBlock: UInt64,
    gasEscrowBalance: UFix64
  ) {
    self.id = id
    self.intentOwner = intentOwner
    self.principalAmount = principalAmount
    self.intentType = intentType
    self.targetAPY = targetAPY
    self.minAmountOut = minAmountOut
    self.maxFeeBPS = maxFeeBPS
    self.minAPY = minAPY
    self.durationDays = durationDays
    self.expiryBlock = expiryBlock
    self.status = status
    self.principalSide = principalSide
    self.recipientEVMAddress = recipientEVMAddress
    self.winningBidID = winningBidID
    self.createdAt = createdAt
    self.executionDeadlineBlock = executionDeadlineBlock
    self.gasEscrowBalance = gasEscrowBalance
  }
}

access(all) fun main(intentID: UInt64): IntentView? {
  let intent = IntentMarketplaceV0_3.getIntent(id: intentID)
  if intent == nil { return nil }
  let i = intent!
  return IntentView(
    id: i.id,
    intentOwner: i.intentOwner.toString(),
    principalAmount: i.principalAmount,
    intentType: i.intentType.rawValue,
    targetAPY: i.targetAPY,
    minAmountOut: i.minAmountOut,
    maxFeeBPS: i.maxFeeBPS,
    minAPY: i.minAPY,
    durationDays: i.durationDays,
    expiryBlock: i.expiryBlock,
    status: i.status.rawValue,
    principalSide: i.principalSide.rawValue,
    recipientEVMAddress: i.recipientEVMAddress,
    winningBidID: i.winningBidID,
    createdAt: i.createdAt,
    executionDeadlineBlock: i.executionDeadlineBlock,
    gasEscrowBalance: i.getGasEscrowBalance()
  )
}
`

// ─────────────────────────────────────────────
// Enum maps
// ─────────────────────────────────────────────

const INTENT_TYPE_MAP: IntentType[] = ['Yield', 'Swap', 'BridgeYield']
const INTENT_STATUS_MAP: IntentStatus[] = [
  'Open',
  'BidSelected',
  'Active',
  'Completed',
  'Cancelled',
  'Expired',
]
const PRINCIPAL_SIDE_MAP: PrincipalSide[] = ['cadence', 'evm']

// ─────────────────────────────────────────────
// Raw Cadence response shape
// ─────────────────────────────────────────────

interface RawIntentView {
  id: string
  intentOwner: string
  principalAmount: string
  intentType: string
  targetAPY: string
  minAmountOut: string | null
  maxFeeBPS: string | null
  minAPY: string | null
  durationDays: string
  expiryBlock: string
  status: string
  principalSide: string
  recipientEVMAddress: string | null
  winningBidID: string | null
  createdAt: string
  executionDeadlineBlock: string
  gasEscrowBalance: string
}

// ─────────────────────────────────────────────
// Parsers
// ─────────────────────────────────────────────

function parseIntentView(raw: RawIntentView): Intent {
  return {
    id: parseInt(raw.id, 10),
    intentOwner: raw.intentOwner,
    principalAmount: parseFloat(raw.principalAmount),
    intentType: INTENT_TYPE_MAP[parseInt(raw.intentType, 10)] ?? 'Yield',
    targetAPY: parseFloat(raw.targetAPY),
    minAmountOut: raw.minAmountOut != null ? parseFloat(raw.minAmountOut) : undefined,
    maxFeeBPS: raw.maxFeeBPS != null ? parseInt(raw.maxFeeBPS, 10) : undefined,
    minAPY: raw.minAPY != null ? parseFloat(raw.minAPY) : undefined,
    durationDays: parseInt(raw.durationDays, 10),
    expiryBlock: parseInt(raw.expiryBlock, 10),
    status: INTENT_STATUS_MAP[parseInt(raw.status, 10)] ?? 'Open',
    principalSide: PRINCIPAL_SIDE_MAP[parseInt(raw.principalSide, 10)] ?? 'cadence',
    recipientEVMAddress: raw.recipientEVMAddress ?? undefined,
    winningBidID: raw.winningBidID != null ? parseInt(raw.winningBidID, 10) : undefined,
    createdAt: parseFloat(raw.createdAt),
    executionDeadlineBlock: parseInt(raw.executionDeadlineBlock, 10),
    gasEscrowBalance: parseFloat(raw.gasEscrowBalance),
  }
}

// ─────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────

/**
 * Fetches all intent IDs that are currently Open.
 * @param cadenceAddress  Address of the deployed IntentMarketplaceV0_3 contract.
 */
export async function getOpenIntentIds(cadenceAddress: string): Promise<number[]> {
  const script = GET_OPEN_INTENT_IDS_SCRIPT.replace(/0xCADENCE_ADDRESS/g, cadenceAddress)
  const result: string[] = await fcl.query({
    cadence: script,
    args: () => [],
  })
  return (result ?? []).map((id) => parseInt(id, 10))
}

/**
 * Fetches a single intent by ID. Returns null if not found.
 * @param id              Intent ID (UInt64).
 * @param cadenceAddress  Address of the deployed IntentMarketplaceV0_3 contract.
 */
export async function getIntent(id: number, cadenceAddress: string): Promise<Intent | null> {
  const script = GET_INTENT_SCRIPT.replace(/0xCADENCE_ADDRESS/g, cadenceAddress)
  const result: RawIntentView | null = await fcl.query({
    cadence: script,
    args: (arg: typeof fcl.arg, t: typeof import('@onflow/types')) => [
      arg(id.toString(), t.UInt64),
    ],
  })
  if (!result) return null
  return parseIntentView(result)
}

/**
 * Fetches all Open intents, resolving each ID to a full Intent object.
 * Runs ID queries in parallel.
 * @param cadenceAddress  Address of the deployed IntentMarketplaceV0_3 contract.
 */
export async function getOpenIntents(cadenceAddress: string): Promise<Intent[]> {
  const ids = await getOpenIntentIds(cadenceAddress)
  const intents = await Promise.all(ids.map((id) => getIntent(id, cadenceAddress)))
  return intents.filter((i): i is Intent => i !== null)
}
