/**
 * client.ts — FlowIntentsClient: the main entry point for solver developers.
 *
 * Usage:
 *   const client = new FlowIntentsClient({
 *     flowPrivateKey: process.env.FLOW_PRIVATE_KEY,
 *     flowAddress: '0xYourAddress',
 *   })
 *
 *   const intents = await client.getOpenIntents()
 *   const txId = await client.submitBid({ intentID: 1, offeredAPY: 8.5, ... })
 */

import * as fcl from '@onflow/fcl'
import * as t from '@onflow/types'
import type { Intent, Bid, BidParams, FlowIntentsConfig } from './types'
import { DEFAULT_CONFIG } from './types'
import { getOpenIntents, getIntent } from './intents'
import { getWinningBid, submitBid as _submitBid, buildAuthorization } from './bids'
import {
  encodeWrapFlowStrategy,
  encodeWrapAndSwapStrategy,
  encodeANKRStakeStrategy,
} from './strategies'

// ─────────────────────────────────────────────
// Execute intent transaction
// ─────────────────────────────────────────────

const EXECUTE_INTENT_CDC = (cadenceAddress: string) => `
import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentExecutorV0_3 from 0x${cadenceAddress.replace(/^0x/, '')}

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
      ?? panic("Cannot borrow solver FlowToken vault")
  }

  execute {
    IntentExecutorV0_3.executeIntentV2(
      intentID: intentID,
      solverAddress: self.solverAddress,
      coa: self.coa,
      solverFlowReceiver: self.solverReceiver,
      recipientEVMAddress: recipientEVMAddress
    )
  }
}
`

// ─────────────────────────────────────────────
// Main client class
// ─────────────────────────────────────────────

interface ResolvedConfig {
  cadenceAddress: string
  composerV4: string
  evmBidRelay: string
  flowEVMRpc: string
  flowAccessNode: string
  flowPrivateKey?: string
  flowAddress?: string
  keyIndex: number
}

export class FlowIntentsClient {
  private readonly cfg: ResolvedConfig

  constructor(config: FlowIntentsConfig = {}) {
    this.cfg = {
      cadenceAddress: config.cadenceAddress ?? DEFAULT_CONFIG.cadenceAddress,
      composerV4: config.composerV4 ?? DEFAULT_CONFIG.composerV4,
      evmBidRelay: config.evmBidRelay ?? DEFAULT_CONFIG.evmBidRelay,
      flowEVMRpc: config.flowEVMRpc ?? DEFAULT_CONFIG.flowEVMRpc,
      flowAccessNode: config.flowAccessNode ?? DEFAULT_CONFIG.flowAccessNode,
      flowPrivateKey: config.flowPrivateKey,
      flowAddress: config.flowAddress,
      keyIndex: config.keyIndex ?? 0,
    }

    // Configure FCL for the correct network
    const isLocal =
      this.cfg.flowAccessNode.includes('localhost') ||
      this.cfg.flowAccessNode.includes('127.0.0.1')
    fcl.config({
      'accessNode.api': this.cfg.flowAccessNode,
      'flow.network': isLocal ? 'local' : 'mainnet',
    })
  }

  // ─────────────────────────────────────────────
  // Read from chain (no signing required)
  // ─────────────────────────────────────────────

  /**
   * Fetch all intents currently in Open status.
   * Runs parallel queries for each intent ID.
   */
  async getOpenIntents(): Promise<Intent[]> {
    return getOpenIntents(this.cfg.cadenceAddress)
  }

  /**
   * Fetch a single intent by ID.
   * @throws if the intent does not exist.
   */
  async getIntent(id: number): Promise<Intent> {
    const intent = await getIntent(id, this.cfg.cadenceAddress)
    if (!intent) {
      throw new Error(`FlowIntentsClient: intent ${id} not found`)
    }
    return intent
  }

  /**
   * Fetch the winning bid for an intent.
   * Returns null if no winner has been selected yet.
   */
  async getWinningBid(intentID: number): Promise<Bid | null> {
    return getWinningBid(intentID, this.cfg.cadenceAddress)
  }

  // ─────────────────────────────────────────────
  // Solver actions (require private key)
  // ─────────────────────────────────────────────

  private requireSigner(): { address: string; privateKey: string } {
    if (!this.cfg.flowPrivateKey || !this.cfg.flowAddress) {
      throw new Error(
        'FlowIntentsClient: flowPrivateKey and flowAddress are required for signing transactions. ' +
        'Pass them in the constructor config.',
      )
    }
    return { address: this.cfg.flowAddress, privateKey: this.cfg.flowPrivateKey }
  }

  /**
   * Submit a bid for an open intent.
   *
   * The solver must be registered in SolverRegistryV0_1 (Cadence side) before bidding.
   *
   * @param params  Bid parameters (intentID, offeredAPY or offeredAmountOut, encodedBatch, etc.)
   * @returns       The sealed Cadence transaction ID.
   */
  async submitBid(params: BidParams): Promise<string> {
    const { address, privateKey } = this.requireSigner()
    return _submitBid(params, this.cfg.cadenceAddress, address, privateKey, this.cfg.keyIndex)
  }

  /**
   * Execute a BidSelected intent as the winning solver.
   *
   * Calls IntentExecutorV0_3.executeIntentV2(), which:
   *   1. Verifies the caller is the winning solver.
   *   2. Bridges the principal vault to the COA's EVM balance.
   *   3. Calls FlowIntentsComposerV4.executeStrategyWithFunds(encodedBatch, recipient).
   *   4. Pays the full gas escrow to the solver.
   *
   * @param intentID              The intent to execute.
   * @param recipientEVMAddress   Optional EVM address override for output tokens.
   *                              If null, uses the intent's default (user's COA).
   * @returns The sealed Cadence transaction ID.
   */
  async executeIntent(intentID: number, recipientEVMAddress?: string): Promise<string> {
    const { address, privateKey } = this.requireSigner()
    const authz = buildAuthorization(address, privateKey, this.cfg.keyIndex)

    const txId: string = await fcl.mutate({
      cadence: EXECUTE_INTENT_CDC(this.cfg.cadenceAddress),
      args: (arg: typeof fcl.arg, _t: typeof t) => [
        arg(intentID.toString(), _t.UInt64),
        arg(recipientEVMAddress ?? null, _t.Optional(_t.String)),
      ],
      proposer: authz,
      payer: authz,
      authorizations: [authz],
      limit: 9999,
    })

    await fcl.tx(txId).onceSealed()
    return txId
  }

  // ─────────────────────────────────────────────
  // Strategy encoding (pure, no chain calls)
  // ─────────────────────────────────────────────

  /**
   * Encode a WFLOW wrap strategy.
   *
   * Single step: WFLOW.deposit{value: amountFlow}()
   * ComposerV4 sweeps the resulting WFLOW to `recipient` after execution.
   *
   * @param amountFlow  Total FLOW to wrap, in whole FLOW (e.g. 1.0).
   * @param recipient   EVM address for output (swept by ComposerV4).
   * @returns 0x-prefixed ABI-encoded StrategyStep[].
   */
  encodeWrapFlowStrategy(amountFlow: number, recipient: string): string {
    return encodeWrapFlowStrategy(amountFlow, recipient)
  }

  /**
   * Encode a 3-step Wrap + Approve + PunchSwap strategy.
   *
   * [0] WFLOW.deposit{value: amountFlow}()
   * [1] WFLOW.approve(ROUTER, swapAmount)
   * [2] ROUTER.swapExactTokensForTokens(swapAmount, minAmountOut, [WFLOW, outputToken], recipient, deadline)
   *
   * Remaining WFLOW (amountFlow - swapAmount) is swept to recipient by ComposerV4.
   *
   * @param amountFlow    Total FLOW to wrap (whole FLOW, e.g. 0.2).
   * @param swapAmount    WFLOW to swap (whole FLOW, e.g. 0.1). Must be ≤ amountFlow.
   * @param outputToken   EVM address of desired output token (e.g. TOKENS.stgUSDC).
   * @param recipient     EVM address to receive swapped tokens.
   * @param minAmountOut  Minimum output (in output token smallest units, e.g. 2981 for 6-decimal stgUSDC).
   * @returns 0x-prefixed ABI-encoded StrategyStep[].
   */
  encodeWrapAndSwapStrategy(
    amountFlow: number,
    swapAmount: number,
    outputToken: string,
    recipient: string,
    minAmountOut: number,
  ): string {
    return encodeWrapAndSwapStrategy(
      amountFlow,
      swapAmount,
      outputToken,
      recipient,
      BigInt(minAmountOut),
    )
  }

  /**
   * Encode an Ankr stake strategy (FLOW → aFLOWEVMb).
   *
   * Single step: AnkrFlowStakingPool.stakeCerts{value: amountFlow}()
   * NOTE: stakeBonds() is paused on mainnet — always use this method.
   *
   * @param amountFlow  Amount of FLOW to stake (whole FLOW, e.g. 0.5).
   * @param recipient   EVM address for reference (aFLOWEVMb swept by ComposerV4).
   * @returns 0x-prefixed ABI-encoded StrategyStep[].
   */
  encodeANKRStakeStrategy(amountFlow: number, recipient: string): string {
    return encodeANKRStakeStrategy(amountFlow, recipient)
  }
}
