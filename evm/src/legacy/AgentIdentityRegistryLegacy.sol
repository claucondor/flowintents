// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAgentIdentityRegistryLegacy} from "./IAgentIdentityRegistryLegacy.sol";

/// @title AgentIdentityRegistry
/// @notice ERC-721 + ERC-8004 compliant agent identity registry
/// @dev One token per address enforced. isActive() and getTokenByOwner() are
///      view functions designed to be called via COA staticCall from Cadence.
///
///      ERC-8004 interface ID is computed as XOR of FlowIntents-specific
///      function selectors:
///        registerAgent(bytes32,string)  = 0x...
///        getIdentity(uint256)           = 0x...
///        getTokenByOwner(address)       = 0x...
///        isActive(uint256)              = 0x...
///      Result: 0x4f9a2e72 (computed below in supportsInterface)
contract AgentIdentityRegistryLegacy is
    ERC721URIStorage,
    Ownable,
    IAgentIdentityRegistryLegacy
{
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice ERC-8004 interface ID (XOR of standard ERC-8004 selectors we comply with)
    /// bytes4(keccak256("register(bytes32,string)"))          = computed
    /// bytes4(keccak256("setMetadata(uint256,bytes32,bytes)"))= computed
    /// bytes4(keccak256("getMetadata(uint256,bytes32)"))      = computed
    /// bytes4(keccak256("setAgentWallet(uint256,address)"))   = computed
    /// bytes4(keccak256("getAgentWallet(uint256)"))           = computed
    /// bytes4(keccak256("unsetAgentWallet(uint256)"))         = computed
    /// Non-compliant deviations:
    ///   - setAgentWallet lacks EIP-712 signature (simplified for COA)
    ///   - register() has 1 overload instead of 3
    ///   - activate()/deactivate() are Flow-specific extensions
    bytes4 public constant ERC8004_INTERFACE_ID =
        bytes4(keccak256("register(bytes32,string)")) ^
        bytes4(keccak256("setMetadata(uint256,bytes32,bytes)")) ^
        bytes4(keccak256("getMetadata(uint256,bytes32)")) ^
        bytes4(keccak256("setAgentWallet(uint256,address)")) ^
        bytes4(keccak256("getAgentWallet(uint256)")) ^
        bytes4(keccak256("unsetAgentWallet(uint256)"));

    /// @notice Legacy interface ID (kept for backward compatibility)
    bytes4 public constant LEGACY_INTERFACE_ID = 0x4f9a2e72;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Counter for token IDs (starts at 1, 0 = "no token")
    uint256 private _nextTokenId;

    /// @notice Maps owner address → token ID (0 means no token)
    mapping(address => uint256) private _ownerToToken;

    /// @notice Full identity records per token ID
    mapping(uint256 => AgentIdentity) private _identities;

    /// @notice Key-value metadata store per token ID (ERC-8004 setMetadata/getMetadata)
    mapping(uint256 => mapping(bytes32 => bytes)) private _metadata;

    /// @notice Agent wallet mapping per token ID (ERC-8004 agentWallet concept)
    mapping(uint256 => address) private _agentWallets;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner)
        ERC721("FlowIntents Agent Identity", "FIAI")
        Ownable(initialOwner)
    {
        _nextTokenId = 1; // start IDs at 1 so 0 can mean "not registered"
    }

    // -------------------------------------------------------------------------
    // ERC-8004 / IAgentIdentityRegistry
    // -------------------------------------------------------------------------

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function registerAgent(bytes32 agentType, string calldata metadataURI)
        external
        override
        returns (uint256 tokenId)
    {
        require(
            _ownerToToken[msg.sender] == 0,
            "AgentIdentityRegistry: address already registered"
        );

        tokenId = _nextTokenId;
        unchecked { _nextTokenId++; }

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        _identities[tokenId] = AgentIdentity({
            tokenId: tokenId,
            owner: msg.sender,
            agentType: agentType,
            metadataURI: metadataURI,
            registeredAt: block.timestamp,
            active: true
        });

        _ownerToToken[msg.sender] = tokenId;

        emit AgentRegistered(tokenId, msg.sender, agentType, metadataURI);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function getIdentity(uint256 tokenId)
        external
        view
        override
        returns (AgentIdentity memory identity)
    {
        _requireOwned(tokenId);
        return _identities[tokenId];
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    /// @dev Cadence can staticCall this to check if an address has an agent
    function getTokenByOwner(address owner)
        external
        view
        override
        returns (uint256 tokenId)
    {
        return _ownerToToken[owner];
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    /// @dev Cadence can staticCall this before submitting a bid
    function isActive(uint256 tokenId)
        external
        view
        override
        returns (bool)
    {
        if (!_existsToken(tokenId)) return false;
        return _identities[tokenId].active;
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function setAgentURI(uint256 tokenId, string calldata newURI)
        external
        override
    {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        _setTokenURI(tokenId, newURI);
        _identities[tokenId].metadataURI = newURI;
        emit AgentURIUpdated(tokenId, newURI);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function deactivate(uint256 tokenId) external override {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(_identities[tokenId].active, "AgentIdentityRegistry: already inactive");
        _identities[tokenId].active = false;
        emit AgentStatusChanged(tokenId, false);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function activate(uint256 tokenId) external override {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(!_identities[tokenId].active, "AgentIdentityRegistry: already active");
        _identities[tokenId].active = true;
        emit AgentStatusChanged(tokenId, true);
    }

    // -------------------------------------------------------------------------
    // ERC-8004 Standard Extensions
    // -------------------------------------------------------------------------

    /// @inheritdoc IAgentIdentityRegistryLegacy
    /// @dev Alias for registerAgent() — ERC-8004 standard name
    function register(bytes32 agentType, string calldata metadataURI)
        external
        override
        returns (uint256 tokenId)
    {
        require(
            _ownerToToken[msg.sender] == 0,
            "AgentIdentityRegistry: address already registered"
        );

        tokenId = _nextTokenId;
        unchecked { _nextTokenId++; }

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        _identities[tokenId] = AgentIdentity({
            tokenId: tokenId,
            owner: msg.sender,
            agentType: agentType,
            metadataURI: metadataURI,
            registeredAt: block.timestamp,
            active: true
        });

        _ownerToToken[msg.sender] = tokenId;

        emit AgentRegistered(tokenId, msg.sender, agentType, metadataURI);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function setMetadata(uint256 tokenId, bytes32 key, bytes calldata value)
        external
        override
    {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        _metadata[tokenId][key] = value;
        emit MetadataUpdated(tokenId, key);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function getMetadata(uint256 tokenId, bytes32 key)
        external
        view
        override
        returns (bytes memory value)
    {
        return _metadata[tokenId][key];
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    /// @dev Simplified for COA context — no EIP-712 signature, owner-only
    function setAgentWallet(uint256 tokenId, address wallet)
        external
        override
    {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(wallet != address(0), "AgentIdentityRegistry: zero wallet");
        _agentWallets[tokenId] = wallet;
        emit AgentWalletChanged(tokenId, wallet);
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function getAgentWallet(uint256 tokenId)
        external
        view
        override
        returns (address wallet)
    {
        return _agentWallets[tokenId];
    }

    /// @inheritdoc IAgentIdentityRegistryLegacy
    function unsetAgentWallet(uint256 tokenId) external override {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        delete _agentWallets[tokenId];
        emit AgentWalletChanged(tokenId, address(0));
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    /// @notice Supports ERC-721, ERC-721Metadata, ERC-165, and ERC-8004
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721URIStorage)
        returns (bool)
    {
        return
            interfaceId == ERC8004_INTERFACE_ID ||
            interfaceId == LEGACY_INTERFACE_ID ||
            super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Transfer hooks — update _ownerToToken on transfer
    // -------------------------------------------------------------------------

    /// @dev Override _update to maintain ownerToToken mapping on transfers/burns
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = super._update(to, tokenId, auth);

        // Clear old owner mapping
        if (from != address(0)) {
            delete _ownerToToken[from];
        }

        // Set new owner mapping (on mint or transfer)
        if (to != address(0)) {
            // Enforce: one token per address (no transfer to address that already has a token)
            require(
                _ownerToToken[to] == 0,
                "AgentIdentityRegistry: destination already has a token"
            );
            _ownerToToken[to] = tokenId;
            // Update stored owner in identity record
            _identities[tokenId].owner = to;
        }

        return from;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _existsToken(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
