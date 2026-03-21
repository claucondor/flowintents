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

// ---- Cadence transactions (inline) ----
// In production these would live in cadence/transactions/*.cdc and be read from disk.

const SUBMIT_BID_CDC = `
import IntentMarketplace from 0xINTENT_CONTRACT
import BidManager from 0xBID_CONTRACT

transaction(
  intentId: UInt64,
  offeredAPY: UFix64,
  agentTokenId: UInt64,
  encodedBatch: String
) {
  prepare(signer: AuthAccount) {
    BidManager.submitBid(
      intentId: intentId,
      offeredAPY: offeredAPY,
      agentTokenId: agentTokenId,
      encodedBatch: encodedBatch,
      solver: signer.address
    )
  }
}
`

const REGISTER_SOLVER_CDC = `
import SolverRegistry from 0xSOLVER_CONTRACT

transaction(agentTokenId: UInt64, evmAddress: String) {
  prepare(signer: AuthAccount) {
    SolverRegistry.registerSolver(
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
    this.erc8004 = new ERC8004Manager(config.evmPrivateKey)
    this.authz = buildAuthorization(config.flowAddress, config.flowPrivateKey)

    fcl.config({
      'accessNode.api': 'https://rest-mainnet.onflow.org',
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

    const tokenId =
      this.config.agentTokenId ??
      (await this.erc8004.getTokenId(this.config.evmAddress))

    const bidArgs = strategyToBidArgs(intent.id, strategy, tokenId)

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
