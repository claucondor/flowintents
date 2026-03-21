/**
 * EventListener — subscribes to Flow Cadence IntentMarketplace events via FCL.
 *
 * Uses fcl.events() (REST transport) for real-time streaming.
 * Automatically re-subscribes on disconnect.
 */

import * as fcl from '@onflow/fcl'
import type { Intent, IntentStatus } from './types/Intent'

// How long to wait before reconnecting after a stream error (ms)
const RECONNECT_DELAY_MS = 5_000

export type IntentCallback = (intent: Intent) => void | Promise<void>
export type ErrorCallback = (err: Error) => void

interface CadenceIntentCreatedEvent {
  intentId: string
  owner: string
  tokenType: string
  principalAmount: string
  targetAPY: string   // stored as UFix64 string in Cadence
  durationDays: string
  expiryBlock: string
  createdAt: string
}

export class EventListener {
  private readonly contractAddress: string
  private readonly accessNodeURL: string
  private onIntentCallback?: IntentCallback
  private onErrorCallback?: ErrorCallback
  private running = false
  private unsubscribe?: () => void

  /**
   * @param contractAddress  Cadence account that deployed IntentMarketplace (without 0x)
   * @param accessNodeURL    FCL access node, e.g. "https://rest-mainnet.onflow.org"
   */
  constructor(
    contractAddress: string,
    accessNodeURL = 'https://rest-mainnet.onflow.org',
  ) {
    this.contractAddress = contractAddress.replace(/^0x/, '')
    this.accessNodeURL = accessNodeURL

    fcl.config({
      'accessNode.api': accessNodeURL,
    })
  }

  onIntent(cb: IntentCallback): this {
    this.onIntentCallback = cb
    return this
  }

  onError(cb: ErrorCallback): this {
    this.onErrorCallback = cb
    return this
  }

  /** Begin listening. Idempotent — calling twice is a no-op. */
  start(): void {
    if (this.running) return
    this.running = true
    this._subscribe()
  }

  /** Stop listening and clean up. */
  stop(): void {
    this.running = false
    if (this.unsubscribe) {
      this.unsubscribe()
      this.unsubscribe = undefined
    }
  }

  private _subscribe(): void {
    if (!this.running) return

    const eventType = `A.${this.contractAddress}.IntentMarketplace.IntentCreated`

    try {
      const subscription = fcl.events(eventType).subscribe(
        (event: { data: CadenceIntentCreatedEvent }) => {
          if (!event?.data) return
          const intent = this._parseEvent(event.data)
          if (this.onIntentCallback) {
            Promise.resolve(this.onIntentCallback(intent)).catch((e: unknown) => {
              this._emitError(e instanceof Error ? e : new Error(String(e)))
            })
          }
        },
        (err: Error) => {
          this._emitError(err)
          this._scheduleReconnect()
        },
      )

      // FCL events().subscribe may return an object with unsubscribe, or a function.
      const sub = subscription as unknown as { unsubscribe?: () => void } | (() => void)
      if (typeof sub === 'function') {
        this.unsubscribe = sub
      } else if (sub && typeof (sub as { unsubscribe?: () => void }).unsubscribe === 'function') {
        this.unsubscribe = () => (sub as { unsubscribe: () => void }).unsubscribe()
      }
    } catch (err) {
      this._emitError(err instanceof Error ? err : new Error(String(err)))
      this._scheduleReconnect()
    }
  }

  private _scheduleReconnect(): void {
    if (!this.running) return
    setTimeout(() => {
      if (this.running) {
        this._subscribe()
      }
    }, RECONNECT_DELAY_MS)
  }

  private _emitError(err: Error): void {
    if (this.onErrorCallback) {
      this.onErrorCallback(err)
    } else {
      console.error('[EventListener]', err.message)
    }
  }

  private _parseEvent(data: CadenceIntentCreatedEvent): Intent {
    return {
      id: data.intentId,
      owner: data.owner,
      tokenType: data.tokenType,
      principalAmount: data.principalAmount,
      targetAPY: parseFloat(data.targetAPY),
      durationDays: parseInt(data.durationDays, 10),
      expiryBlock: parseInt(data.expiryBlock, 10),
      status: 'Open' as IntentStatus,
      createdAt: parseInt(data.createdAt, 10),
    }
  }
}
