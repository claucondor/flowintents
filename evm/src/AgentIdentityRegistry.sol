// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAgentIdentityRegistry} from "./interfaces/IAgentIdentityRegistry.sol";

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
contract AgentIdentityRegistry is
    ERC721URIStorage,
    Ownable,
    IAgentIdentityRegistry
{
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice ERC-8004 interface ID (XOR of FlowIntents identity selectors)
    /// bytes4(keccak256("registerAgent(bytes32,string)")) = 0x9e458a16
    /// bytes4(keccak256("getIdentity(uint256)"))          = 0x17c275f9
    /// bytes4(keccak256("getTokenByOwner(address)"))      = 0x33d5c13a
    /// bytes4(keccak256("isActive(uint256)"))             = 0x9f8a13d7
    /// XOR: 0x9e458a16 ^ 0x17c275f9 ^ 0x33d5c13a ^ 0x9f8a13d7 = 0x4f9a2e72
    bytes4 public constant ERC8004_INTERFACE_ID = 0x4f9a2e72;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Counter for token IDs (starts at 1, 0 = "no token")
    uint256 private _nextTokenId;

    /// @notice Maps owner address → token ID (0 means no token)
    mapping(address => uint256) private _ownerToToken;

    /// @notice Full identity records per token ID
    mapping(uint256 => AgentIdentity) private _identities;

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

    /// @inheritdoc IAgentIdentityRegistry
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

    /// @inheritdoc IAgentIdentityRegistry
    function getIdentity(uint256 tokenId)
        external
        view
        override
        returns (AgentIdentity memory identity)
    {
        _requireOwned(tokenId);
        return _identities[tokenId];
    }

    /// @inheritdoc IAgentIdentityRegistry
    /// @dev Cadence can staticCall this to check if an address has an agent
    function getTokenByOwner(address owner)
        external
        view
        override
        returns (uint256 tokenId)
    {
        return _ownerToToken[owner];
    }

    /// @inheritdoc IAgentIdentityRegistry
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

    /// @inheritdoc IAgentIdentityRegistry
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

    /// @inheritdoc IAgentIdentityRegistry
    function deactivate(uint256 tokenId) external override {
        require(
            ownerOf(tokenId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(_identities[tokenId].active, "AgentIdentityRegistry: already inactive");
        _identities[tokenId].active = false;
        emit AgentStatusChanged(tokenId, false);
    }

    /// @inheritdoc IAgentIdentityRegistry
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
