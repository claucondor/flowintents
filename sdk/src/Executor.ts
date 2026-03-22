/**
 * Executor — submits Cadence transactions via FCL using a private-key authorizer.
 *
 * Supports:
 *   - submitBid(intentId, strategy)  — calls submitBid.cdc after verifying ERC-8004
 *   - registerSolver()               — calls registerSolver.cdc
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import { ec as EC } from 'elliptic'
import { SHA3 } from 'sha3'
import type { InteractionAccount } from '@onflow/typedefs'
import type { SolverConfig } from './types/SolverConfig'
import type { Intent } from './types/Intent'
import type { Strategy } from './types/Strategy'
import { ERC8004Manager } from './ERC8004Manager'
import { buildBidArgs, strategyToBidArgs } from './BidBuilder'

// ---- FCL private-key authorization ----

const ec = new EC('p256')

function hashMessage(msg: string): Buffer {
  const sha = new SHA3(256)
  sha.update(Buffer.from(msg, 'hex'))
  return Buffer.from(sha.digest())
}

function signWithKey(privateKey: string, msg: string): string {
  const key = ec.keyFromPrivate(Buffer.from(privateKey, 'hex'))
  const sig = key.sign(hashMessage(msg))
  const n = 32
  const r = sig.r.toArrayLike(Buffer, 'be', n)
  const s = sig.s.toArrayLike(Buffer, 'be', n)
  return Buffer.concat([r, s]).toString('hex')
}

/**
 * Returns a FCL authorization function for a given Flow account + private key.
 * Typed to match FCL's AuthorizationFn signature.
 */
function buildAuthorization(
  address: string,
  privateKey: string,
  keyIndex = 0,
): (acct: InteractionAccount) => InteractionAccount {
  return (acct: InteractionAccount): InteractionAccount => {
    return {
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
    }
  }
}

// ---- Cadence contract addresses (from cadence/scripts/deploy/addresses.json) ----

const CADENCE_ADDRESSES = {
  IntentMarketplaceV0_1: 'f8d6e0586b0a20c7',
  SolverRegistryV0_1: 'f8d6e0586b0a20c7',
  BidManagerV0_1: 'f8d6e0586b0a20c7',
  IntentExecutorV0_1: 'f8d6e0586b0a20c7',
}

// ---- Cadence transactions (inline) ----

/**
 * Updated submitBid transaction matching Sprint 2 Cadence signature:
 *   intentID: UInt64
 *   offeredAPY: UFix64?           (Yield / BridgeYield)
 *   offeredAmountOut: UFix64?     (Swap)
 *   encodedBatch: [UInt8]         (ABI-encoded BatchStep[])
 *   solverEVMAddress: String
 *   targetChain: String?
 *   estimatedFeeBPS: UInt64?
 */
const SUBMIT_BID_CDC = `
import IntentMarketplaceV0_1 from 0x${CADENCE_ADDRESSES.IntentMarketplaceV0_1}
import BidManagerV0_1 from 0x${CADENCE_ADDRESSES.BidManagerV0_1}

transaction(
  intentID: UInt64,
  offeredAPY: UFix64?,
  offeredAmountOut: UFix64?,
  encodedBatch: [UInt8],
  solverEVMAddress: String,
  targetChain: String?,
  estimatedFeeBPS: UInt64?
) {
  prepare(signer: &Account) {
    BidManagerV0_1.submitBid(
      intentID: intentID,
      offeredAPY: offeredAPY,
      offeredAmountOut: offeredAmountOut,
      encodedBatch: encodedBatch,
      solverEVMAddress: solverEVMAddress,
      targetChain: targetChain,
      estimatedFeeBPS: estimatedFeeBPS,
      solver: signer.address
    )
  }
}
`

const REGISTER_SOLVER_CDC = `
import SolverRegistryV0_1 from 0x${CADENCE_ADDRESSES.SolverRegistryV0_1}

transaction(agentTokenId: UInt64, evmAddress: String) {
  prepare(signer: &Account) {
    SolverRegistryV0_1.registerSolver(
      agentTokenId: agentTokenId,
      evmAddress: evmAddress,
      solver: signer.address
    )
  }
}
`

// ---- Executor class ----

export class Executor {
  private readonly config: SolverConfig
  private readonly erc8004: ERC8004Manager
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private readonly authz: any

  constructor(config: SolverConfig) {
    this.config = config
    // Use emulator RPC by default; override rpcUrl in config for mainnet
    this.erc8004 = new ERC8004Manager(config.evmPrivateKey)
    this.authz = buildAuthorization(config.flowAddress, config.flowPrivateKey)

    // FCL configured for Flow emulator
    fcl.config({
      'accessNode.api': 'http://localhost:8080',
      'flow.network': 'local',
    })
  }

  /**
   * Submit a bid for an intent.
   * Verifies ERC-8004 registration first — throws if not registered.
   */
  async submitBid(intent: Intent, strategy: Strategy): Promise<string> {
    // Guard: must have an ERC-8004 token
    const registered = await this.erc8004.isRegistered(this.config.evmAddress)
    if (!registered) {
      throw new Error(
        `Executor.submitBid: solver ${this.config.evmAddress} is not registered ` +
        `as an ERC-8004 agent. Call registerSolver() first.`,
      )
    }

    const bidArgs = strategyToBidArgs(
      intent.id,
      strategy,
      this.config.agentTokenId ?? 0,
      this.config.evmAddress,
    )

    const txId: string = await fcl.mutate({
      cadence: SUBMIT_BID_CDC,
      args: (_arg: typeof fcl.arg, _t: typeof t) => buildBidArgs(bidArgs),
      proposer: this.authz,
      payer: this.authz,
      authorizations: [this.authz],
      limit: 999,
    })

    await fcl.tx(txId).onceSealed()
    return txId
  }

  /**
   * Register this solver in the Cadence SolverRegistry.
   * Requires the ERC-8004 token to already be minted on Flow EVM.
   */
  async registerSolver(): Promise<string> {
    const tokenId =
      this.config.agentTokenId ??
      (await this.erc8004.getTokenId(this.config.evmAddress))
    if (tokenId === 0) {
      throw new Error(
        `Executor.registerSolver: no ERC-8004 token found for ${this.config.evmAddress}. ` +
        `Call ERC8004Manager.registerAgent() first.`,
      )
    }

    const txId: string = await fcl.mutate({
      cadence: REGISTER_SOLVER_CDC,
      args: (_arg: typeof fcl.arg, _t: typeof t) => [
        fcl.arg(tokenId.toString(), t.UInt64),
        fcl.arg(this.config.evmAddress, t.String),
      ],
      proposer: this.authz,
      payer: this.authz,
      authorizations: [this.authz],
      limit: 999,
    })

    await fcl.tx(txId).onceSealed()
    return txId
  }
}
