/**
 * Integration test for EventListener.
 * Requires: flow emulator running on localhost.
 * Run with: npm run test:integration
 */

import { describe, it, expect, vi, afterEach } from 'vitest'
import { EventListener } from '../../src/EventListener'

// These tests mock FCL to avoid requiring a live emulator in CI.
// For live testing against the emulator, remove the mock and run `flow emulator start` first.

vi.mock('@onflow/fcl', () => {
  return {
    config: vi.fn(),
    events: vi.fn(() => ({
      subscribe: vi.fn((onEvent, _onError) => {
        // Simulate one event being emitted
        setTimeout(() => {
          onEvent({
            data: {
              intentId: '1',
              owner: '0xf8d6e0586b0a20c7',
              tokenType: 'USDC',
              principalAmount: '500.00000000',
              targetAPY: '5.00000000',
              durationDays: '30',
              expiryBlock: '9999',
              createdAt: '1700000000',
            },
          })
        }, 10)
        return { unsubscribe: vi.fn() }
      }),
    })),
  }
})

describe('EventListener (integration)', () => {
  afterEach(() => {
    vi.clearAllMocks()
  })

  it('parses an IntentCreated event into a typed Intent', async () => {
    const listener = new EventListener(
      'f8d6e0586b0a20c7',
      'http://localhost:8888',
    )

    const received = await new Promise<import('../../src/types/Intent').Intent>((resolve) => {
      listener.onIntent((intent) => {
        resolve(intent)
      })
      listener.start()
    })

    listener.stop()

    expect(received.id).toBe('1')
    expect(received.owner).toBe('0xf8d6e0586b0a20c7')
    expect(received.tokenType).toBe('USDC')
    expect(received.principalAmount).toBe('500.00000000')
    expect(received.targetAPY).toBe(5.0)
    expect(received.durationDays).toBe(30)
    expect(received.status).toBe('Open')
  })
})
