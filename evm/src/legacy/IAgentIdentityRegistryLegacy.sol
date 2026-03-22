// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentIdentityRegistry
/// @notice ERC-8004 compatible agent identity registry interface
/// @dev Extends ERC-721 with agent-specific identity functions
///      ERC-8004 interface ID = bytes4(keccak256("registerAgent(bytes32,string)")) ^
///                               bytes4(keccak256("getIdentity(uint256)")) ^
///                               bytes4(keccak256("getTokenByOwner(address)")) ^
///                               bytes4(keccak256("isActive(uint256)"))
///      = 0x4e2312e0 (computed from FlowIntents-specific selectors)
interface IAgentIdentityRegistryLegacy {
    /// @notice Full agent identity record
    struct AgentIdentity {
        uint256 tokenId;
        address owner;
        bytes32 agentType;   // keccak256 of role string e.g. keccak256("SOLVER")
        string metadataURI;  // IPFS or HTTPS URI to agent registration file
        uint256 registeredAt;
        bool active;
    }

    /// @notice Emitted when a new agent is registered
    event AgentRegistered(
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 indexed agentType,
        string metadataURI
    );

    /// @notice Emitted when an agent's metadata URI is updated
    event AgentURIUpdated(uint256 indexed tokenId, string newURI);

    /// @notice Emitted when an agent is activated or deactivated
    event AgentStatusChanged(uint256 indexed tokenId, bool active);

    /// @notice Register a new agent identity (one per address)
    /// @param agentType keccak256 of the agent role (e.g. keccak256("SOLVER"))
    /// @param metadataURI URI pointing to the agent registration JSON
    /// @return tokenId The newly minted NFT token ID (= agentId in ERC-8004)
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
    /// @param owner The owner address to query
    /// @return tokenId The token ID owned by this address, 0 if none
    function getTokenByOwner(address owner)
        external
        view
        returns (uint256 tokenId);

    /// @notice Check whether an agent is currently active
    /// @param tokenId The agent token ID
    /// @return True if the agent is active
    function isActive(uint256 tokenId) external view returns (bool);

    /// @notice Update the metadata URI for an agent (owner only)
    /// @param tokenId The agent token ID
    /// @param newURI The new metadata URI
    function setAgentURI(uint256 tokenId, string calldata newURI) external;

    /// @notice Deactivate an agent (owner only)
    /// @param tokenId The agent token ID
    function deactivate(uint256 tokenId) external;

    /// @notice Reactivate a previously deactivated agent (owner only)
    /// @param tokenId The agent token ID
    function activate(uint256 tokenId) external;

    // -------------------------------------------------------------------------
    // ERC-8004 Standard Extensions
    // -------------------------------------------------------------------------

    /// @notice Emitted when metadata key-value pair is updated
    event MetadataUpdated(uint256 indexed tokenId, bytes32 indexed key);

    /// @notice Emitted when agent wallet is changed
    event AgentWalletChanged(uint256 indexed tokenId, address indexed wallet);

    /// @notice ERC-8004 standard register alias (delegates to registerAgent)
    /// @param agentType keccak256 of the agent role
    /// @param metadataURI URI pointing to the agent registration JSON
    /// @return tokenId The newly minted NFT token ID
    function register(bytes32 agentType, string calldata metadataURI)
        external
        returns (uint256 tokenId);

    /// @notice Set a metadata key-value pair for an agent (owner only)
    /// @param tokenId The agent token ID
    /// @param key The metadata key
    /// @param value The metadata value (arbitrary bytes)
    function setMetadata(uint256 tokenId, bytes32 key, bytes calldata value) external;

    /// @notice Get a metadata value for an agent
    /// @param tokenId The agent token ID
    /// @param key The metadata key
    /// @return value The metadata value
    function getMetadata(uint256 tokenId, bytes32 key)
        external
        view
        returns (bytes memory value);

    /// @notice Set the agent wallet address (simplified, no EIP-712 — owner only)
    /// @param tokenId The agent token ID
    /// @param wallet The wallet address to associate
    function setAgentWallet(uint256 tokenId, address wallet) external;

    /// @notice Get the agent wallet address
    /// @param tokenId The agent token ID
    /// @return wallet The associated wallet address
    function getAgentWallet(uint256 tokenId)
        external
        view
        returns (address wallet);

    /// @notice Remove the agent wallet association (owner only)
    /// @param tokenId The agent token ID
    function unsetAgentWallet(uint256 tokenId) external;
}
