/**
 * ERC8004Manager — manages ERC-8004 Agent NFT registration on Flow EVM (chainId 747).
 *
 * CRITICAL: a solver CANNOT submit bids without a registered ERC-8004 token.
 */

import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  parseAbi,
  type PublicClient,
  type WalletClient,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// ---- Flow EVM chain definition ----
export const flowEvmMainnet = defineChain({
  id: 747,
  name: 'Flow EVM Mainnet',
  network: 'flow-evm',
  nativeCurrency: {
    decimals: 18,
    name: 'Flow',
    symbol: 'FLOW',
  },
  rpcUrls: {
    default: { http: ['https://mainnet.evm.nodes.onflow.org'] },
    public: { http: ['https://mainnet.evm.nodes.onflow.org'] },
  },
  blockExplorers: {
    default: { name: 'Flowscan', url: 'https://evm.flowscan.io' },
  },
})

/**
 * Minimal ABI for the ERC-8004 AgentRegistry contract.
 * Actual deployed ABI may differ; adjust if contract interface changes.
 */
const ERC8004_ABI = parseAbi([
  // Read
  'function getTokenByOwner(address owner) view returns (uint256)',
  'function getMultiplier(uint256 tokenId) view returns (uint256)',
  // Write
  'function registerAgent(string agentType, string metadataURI) returns (uint256)',
])

/**
 * Address of the ERC-8004 AgentRegistry on Flow EVM mainnet.
 * Replace with the actual deployed contract address.
 */
const ERC8004_CONTRACT = '0x0000000000000000000000000000000000000000' as `0x${string}`

export class ERC8004Manager {
  private readonly publicClient: PublicClient
  private walletClient?: WalletClient
  private readonly contractAddress: `0x${string}`

  constructor(
    evmPrivateKey?: string,
    contractAddress: `0x${string}` = ERC8004_CONTRACT,
    rpcUrl?: string,
  ) {
    const transport = http(rpcUrl ?? 'https://mainnet.evm.nodes.onflow.org')

    this.publicClient = createPublicClient({
      chain: flowEvmMainnet,
      transport,
    }) as PublicClient

    if (evmPrivateKey) {
      const account = privateKeyToAccount(
        (evmPrivateKey.startsWith('0x') ? evmPrivateKey : `0x${evmPrivateKey}`) as `0x${string}`,
      )
      this.walletClient = createWalletClient({
        account,
        chain: flowEvmMainnet,
        transport,
      })
    }

    this.contractAddress = contractAddress
  }

  /**
   * Returns true if the given EVM address has a registered ERC-8004 agent token.
   */
  async isRegistered(evmAddress: string): Promise<boolean> {
    const tokenId = await this.getTokenId(evmAddress)
    return tokenId > 0
  }

  /**
   * Returns the ERC-8004 token ID for the given address (0 if not registered).
   */
  async getTokenId(evmAddress: string): Promise<number> {
    const id = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: ERC8004_ABI,
      functionName: 'getTokenByOwner',
      args: [evmAddress as `0x${string}`],
    })
    return Number(id)
  }

  /**
   * Registers a new ERC-8004 agent.
   * Requires the EVM private key to be provided at construction time.
   * @param agentType  e.g. "yield-optimizer"
   * @param metadataURI  IPFS URI or HTTP URL with agent metadata JSON
   * @returns The newly minted token ID
   */
  async registerAgent(agentType: string, metadataURI: string): Promise<number> {
    if (!this.walletClient) {
      throw new Error('ERC8004Manager: evmPrivateKey is required to registerAgent')
    }

    const account = this.walletClient.account
    if (!account) throw new Error('ERC8004Manager: wallet account not set')

    const hash = await this.walletClient.writeContract({
      address: this.contractAddress,
      abi: ERC8004_ABI,
      functionName: 'registerAgent',
      args: [agentType, metadataURI],
      chain: flowEvmMainnet,
      account,
    })

    // Wait for receipt
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash })

    if (receipt.status !== 'success') {
      throw new Error(`ERC8004Manager: registerAgent tx reverted (hash: ${hash})`)
    }

    // Derive token ID from the event logs or re-read
    const tokenId = await this.getTokenId(account.address)
    if (tokenId === 0) {
      throw new Error('ERC8004Manager: registration succeeded but tokenId still 0 — check contract')
    }

    return tokenId
  }

  /**
   * Returns the multiplier for a given token ID (1e18-based, so 1x = 1_000_000_000_000_000_000n).
   */
  async getMultiplier(tokenId: number): Promise<number> {
    const raw = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: ERC8004_ABI,
      functionName: 'getMultiplier',
      args: [BigInt(tokenId)],
    })
    return Number(raw)
  }
}
