import { describe, it, expect, vi, beforeEach } from 'vitest'
import { ERC8004Manager } from '../../src/ERC8004Manager'

// We mock viem's createPublicClient and createWalletClient to avoid real network calls.
vi.mock('viem', async (importOriginal) => {
  const actual = await importOriginal<typeof import('viem')>()
  return {
    ...actual,
    createPublicClient: vi.fn(() => ({
      readContract: vi.fn(),
      waitForTransactionReceipt: vi.fn(),
    })),
    createWalletClient: vi.fn(() => ({
      writeContract: vi.fn(),
      account: { address: '0xabc' as `0x${string}` },
    })),
  }
})

describe('ERC8004Manager', () => {
  let manager: ERC8004Manager

  beforeEach(() => {
    manager = new ERC8004Manager(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    )
  })

  it('isRegistered returns false when tokenId is 0', async () => {
    const { createPublicClient } = await import('viem')
    const mockPublic = vi.mocked(createPublicClient)()
    vi.mocked(mockPublic.readContract).mockResolvedValue(0n)

    // Manually inject the mock client
    ;(manager as unknown as { publicClient: typeof mockPublic }).publicClient = mockPublic

    const result = await manager.isRegistered('0xabc')
    expect(result).toBe(false)
  })

  it('isRegistered returns true when tokenId > 0', async () => {
    const { createPublicClient } = await import('viem')
    const mockPublic = vi.mocked(createPublicClient)()
    vi.mocked(mockPublic.readContract).mockResolvedValue(3n)

    ;(manager as unknown as { publicClient: typeof mockPublic }).publicClient = mockPublic

    const result = await manager.isRegistered('0xabc')
    expect(result).toBe(true)
  })

  it('getMultiplier returns numeric value', async () => {
    const { createPublicClient } = await import('viem')
    const mockPublic = vi.mocked(createPublicClient)()
    vi.mocked(mockPublic.readContract).mockResolvedValue(1_000_000_000_000_000_000n)

    ;(manager as unknown as { publicClient: typeof mockPublic }).publicClient = mockPublic

    const multiplier = await manager.getMultiplier(1)
    expect(multiplier).toBe(1_000_000_000_000_000_000)
  })
})
