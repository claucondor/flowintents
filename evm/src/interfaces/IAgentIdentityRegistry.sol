// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentIdentityRegistry
/// @notice ERC-8004 compliant agent identity registry interface with Flow COA extensions
/// @dev Standard ERC-8004 functions are listed first, followed by Flow-specific extensions.
///
///      ERC-8004 standard functions (from the EIP specification):
///        register()                                                          -> uint256
///        register(string)                                                    -> uint256
///        register(string,MetadataEntry[])                                    -> uint256
///        setAgentURI(uint256,string)
///        getMetadata(uint256,string)                                         -> bytes
///        setMetadata(uint256,string,bytes)
///        setAgentWallet(uint256,address,uint256,bytes)
///        getAgentWallet(uint256)                                             -> address
///        unsetAgentWallet(uint256)
///
///      Flow COA extensions (marked FLOW-EXTENSION):
///        registerAgent(bytes32,string)                                       -> uint256
///        getIdentity(uint256)                                                -> AgentIdentity
///        getTokenByOwner(address)                                            -> uint256
///        isActive(uint256)                                                   -> bool
///        activate(uint256)
///        deactivate(uint256)
interface IAgentIdentityRegistry {

    // =========================================================================
    // ERC-8004 Standard Structs
    // =========================================================================

    /// @notice Key-value metadata entry (ERC-8004 standard)
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    // =========================================================================
    // FLOW-EXTENSION: Agent identity struct (not in ERC-8004)
    // =========================================================================

    /// @notice Full agent identity record
    struct AgentIdentity {
        uint256 tokenId;
        address owner;
        bytes32 agentType;   // keccak256 of role string e.g. keccak256("SOLVER")
        string metadataURI;  // IPFS or HTTPS URI to agent registration file
        uint256 registeredAt;
        bool active;
    }

    // =========================================================================
    // ERC-8004 Standard Events
    // =========================================================================

    /// @notice Emitted when a new agent is registered (ERC-8004 standard)
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice Emitted when an agent URI is updated (ERC-8004 standard)
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    /// @notice Emitted when metadata is set (ERC-8004 standard)
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes metadataValue
    );

    // =========================================================================
    // FLOW-EXTENSION: Custom Events
    // =========================================================================

    /// @notice Emitted when an agent is registered via the legacy registerAgent() path
    event AgentRegistered(
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 indexed agentType,
        string metadataURI
    );

    /// @notice Emitted when an agent's metadata URI is updated via setAgentURI()
    event AgentURIUpdated(uint256 indexed tokenId, string newURI);

    /// @notice Emitted when an agent is activated or deactivated
    event AgentStatusChanged(uint256 indexed tokenId, bool active);

    // =========================================================================
    // ERC-8004 Standard Functions
    // =========================================================================

    /// @notice Register a new agent with no URI (ERC-8004 standard)
    /// @return agentId The newly minted NFT token ID
    function register() external returns (uint256 agentId);

    /// @notice Register a new agent with a URI (ERC-8004 standard)
    /// @param agentURI URI pointing to the agent registration JSON
    /// @return agentId The newly minted NFT token ID
    function register(string calldata agentURI) external returns (uint256 agentId);

    /// @notice Register a new agent with URI and metadata (ERC-8004 standard)
    /// @param agentURI URI pointing to the agent registration JSON
    /// @param metadata Array of key-value metadata entries
    /// @return agentId The newly minted NFT token ID
    function register(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        returns (uint256 agentId);

    /// @notice Update the metadata URI for an agent (ERC-8004 standard)
    /// @param agentId The agent token ID
    /// @param newURI The new metadata URI
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Get a metadata value by key (ERC-8004 standard)
    /// @param agentId The agent token ID
    /// @param metadataKey The metadata key string
    /// @return The metadata value
    function getMetadata(uint256 agentId, string memory metadataKey)
        external
        view
        returns (bytes memory);

    /// @notice Set a metadata key-value pair (ERC-8004 standard)
    /// @param agentId The agent token ID
    /// @param metadataKey The metadata key string
    /// @param metadataValue The metadata value
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue)
        external;

    /// @notice Set the agent wallet with EIP-712 signature verification (ERC-8004 standard)
    /// @param agentId The agent token ID
    /// @param newWallet The wallet address to associate
    /// @param deadline Signature expiry timestamp
    /// @param signature EIP-712 or ERC-1271 signature from newWallet
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature)
        external;

    /// @notice Get the agent wallet address (ERC-8004 standard)
    /// @param agentId The agent token ID
    /// @return The associated wallet address
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Remove the agent wallet association (ERC-8004 standard)
    /// @param agentId The agent token ID
    function unsetAgentWallet(uint256 agentId) external;

    // =========================================================================
    // FLOW-EXTENSION: Legacy / COA Functions
    // =========================================================================

    /// @notice Register a new agent identity with type and URI (legacy alias)
    /// @param agentType keccak256 of the agent role (e.g. keccak256("SOLVER"))
    /// @param metadataURI URI pointing to the agent registration JSON
    /// @return tokenId The newly minted NFT token ID
    function registerAgent(bytes32 agentType, string calldata metadataURI)
        external
        returns (uint256 tokenId);

    /// @notice Get the full identity record for a token
    /// @param tokenId The agent token ID
    /// @return identity The full AgentIdentity struct
    function getIdentity(uint256 tokenId)
        external
        view
        returns (AgentIdentity memory identity);

    /// @notice Look up token ID by owner address (one token per address)
    /// @dev Cadence can staticCall this via COA to resolve agent identity
    /// @param owner The owner address to query
    /// @return tokenId The token ID owned by this address, 0 if none
    function getTokenByOwner(address owner)
        external
        view
        returns (uint256 tokenId);

    /// @notice Check whether an agent is currently active
    /// @dev Cadence can staticCall this before submitting a bid
    /// @param tokenId The agent token ID
    /// @return True if the agent is active
    function isActive(uint256 tokenId) external view returns (bool);

    /// @notice Deactivate an agent (owner only)
    /// @param tokenId The agent token ID
    function deactivate(uint256 tokenId) external;

    /// @notice Reactivate a previously deactivated agent (owner only)
    /// @param tokenId The agent token ID
    function activate(uint256 tokenId) external;
}
