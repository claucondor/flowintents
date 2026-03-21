/**
 * ERC8004Manager — manages ERC-8004 Agent NFT registration on Flow EVM (chainId 747).
 *
 * CRITICAL: a solver CANNOT submit bids without a registered ERC-8004 token.
 *
 * Contract split (evm-core):
 *   AgentIdentityRegistry   — minting, ownership, isActive
 *   AgentReputationRegistry — score, multiplier
 *
 * agentType is bytes32 (keccak256 of a role string, e.g. keccak256("SOLVER")).
 * The helper encodeAgentType() converts a plain string for convenience.
 */

import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  keccak256,
  toBytes,
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
 * ABI for the ERC-8004 AgentIdentityRegistry contract (evm-core).
 * Source: evm/src/interfaces/IAgentIdentityRegistry.sol
 *
 * IMPORTANT: agentType is bytes32 — pass keccak256(toBytes("SOLVER")),
 * NOT a plain string. Use encodeAgentType() below.
 */
const ERC8004_IDENTITY_ABI = parseAbi([
  // Read
  'function getTokenByOwner(address owner) view returns (uint256)',
  'function isActive(uint256 tokenId) view returns (bool)',
  // Write — agentType MUST be bytes32 (keccak256 of role string)
  'function registerAgent(bytes32 agentType, string metadataURI) returns (uint256)',
])

/**
 * ABI for the ERC-8004 AgentReputationRegistry contract (evm-core).
 * Source: evm/src/AgentReputationRegistry.sol
 * getMultiplier lives here, NOT on AgentIdentityRegistry.
 */
const ERC8004_REPUTATION_ABI = parseAbi([
  'function getMultiplier(uint256 tokenId) view returns (uint256)',
])

/**
 * Address of the ERC-8004 AgentIdentityRegistry on Flow EVM mainnet.
 * Replace with the actual deployed contract address from evm-core.
 * See sdk/PENDING.md for details.
 */
const ERC8004_IDENTITY_CONTRACT = '0x0000000000000000000000000000000000000000' as `0x${string}`

/**
 * Address of the ERC-8004 AgentReputationRegistry on Flow EVM mainnet.
 * Replace with the actual deployed contract address from evm-core.
 * See sdk/PENDING.md for details.
 */
const ERC8004_REPUTATION_CONTRACT = '0x0000000000000000000000000000000000000000' as `0x${string}`

/**
 * Convert a plain role string (e.g. "SOLVER") to the bytes32 agentType
 * expected by AgentIdentityRegistry.registerAgent().
 */
export function encodeAgentType(roleString: string): `0x${string}` {
  return keccak256(toBytes(roleString))
}

export class ERC8004Manager {
  private readonly publicClient: PublicClient
  private walletClient?: WalletClient
  private readonly contractAddress: `0x${string}`
  private readonly reputationContractAddress: `0x${string}`

  constructor(
    evmPrivateKey?: string,
    contractAddress: `0x${string}` = ERC8004_IDENTITY_CONTRACT,
    rpcUrl?: string,
    reputationContractAddress: `0x${string}` = ERC8004_REPUTATION_CONTRACT,
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
    this.reputationContractAddress = reputationContractAddress
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
      abi: ERC8004_IDENTITY_ABI,
      functionName: 'getTokenByOwner',
      args: [evmAddress as `0x${string}`],
    })
    return Number(id)
  }

  /**
   * Registers a new ERC-8004 agent on AgentIdentityRegistry.
   * Requires the EVM private key to be provided at construction time.
   *
   * @param agentType  Plain role string, e.g. "SOLVER" — converted to bytes32 internally.
   *                   Alternatively pass a pre-computed 0x-prefixed bytes32 hex string (66 chars).
   * @param metadataURI  IPFS URI or HTTP URL with agent metadata JSON
   * @returns The newly minted token ID
   */
  async registerAgent(agentType: string, metadataURI: string): Promise<number> {
    if (!this.walletClient) {
      throw new Error('ERC8004Manager: evmPrivateKey is required to registerAgent')
    }

    const account = this.walletClient.account
    if (!account) throw new Error('ERC8004Manager: wallet account not set')

    // Convert plain role string → bytes32; already-hex strings are passed through.
    const agentTypeBytes32: `0x${string}` =
      agentType.startsWith('0x') && agentType.length === 66
        ? (agentType as `0x${string}`)
        : encodeAgentType(agentType)

    const hash = await this.walletClient.writeContract({
      address: this.contractAddress,
      abi: ERC8004_IDENTITY_ABI,
      functionName: 'registerAgent',
      args: [agentTypeBytes32, metadataURI],
      chain: flowEvmMainnet,
      account,
    })

    // Wait for receipt
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash })

    if (receipt.status !== 'success') {
      throw new Error(`ERC8004Manager: registerAgent tx reverted (hash: ${hash})`)
    }

    // Derive token ID by re-reading ownership mapping
    const tokenId = await this.getTokenId(account.address)
    if (tokenId === 0) {
      throw new Error('ERC8004Manager: registration succeeded but tokenId still 0 — check contract')
    }

    return tokenId
  }

  /**
   * Returns the multiplier for a given token ID from AgentReputationRegistry
   * (1e18-based, so 1x = 1_000_000_000_000_000_000n).
   *
   * NOTE: Reads from reputationContractAddress (AgentReputationRegistry),
   * NOT from the identity contract (AgentIdentityRegistry).
   */
  async getMultiplier(tokenId: number): Promise<number> {
    const raw = await this.publicClient.readContract({
      address: this.reputationContractAddress,
      abi: ERC8004_REPUTATION_ABI,
      functionName: 'getMultiplier',
      args: [BigInt(tokenId)],
    })
    return Number(raw)
  }
}
