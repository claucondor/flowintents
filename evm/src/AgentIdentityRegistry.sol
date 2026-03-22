// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IAgentIdentityRegistry} from "./interfaces/IAgentIdentityRegistry.sol";

/// @title AgentIdentityRegistry
/// @notice ERC-8004 compliant agent identity registry with Flow COA extensions
/// @dev Implements the full ERC-8004 Identity Registry specification:
///      - Three register() overloads (no-arg, URI-only, URI+metadata)
///      - setAgentURI(), getMetadata(), setMetadata()
///      - setAgentWallet() with EIP-712 signature verification
///      - getAgentWallet(), unsetAgentWallet()
///
///      Flow COA extensions (marked FLOW-EXTENSION):
///      - registerAgent(bytes32,string) — legacy alias with agentType + one-per-address
///      - getIdentity(uint256) — full identity struct
///      - getTokenByOwner(address) — reverse lookup for COA staticCall
///      - isActive(uint256) — status check for SolverRegistryV0_2
///      - activate(uint256) / deactivate(uint256) — lifecycle management
///      - One-token-per-address enforcement (needed for COA identity model)
///
///      ERC-8004 interfaceId = XOR of standard function selectors (see ERC8004_INTERFACE_ID).
contract AgentIdentityRegistry is
    ERC721URIStorage,
    Ownable,
    EIP712,
    IAgentIdentityRegistry
{
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice ERC-8004 interface ID: XOR of all standard ERC-8004 Identity Registry
    ///         function selectors (NOT including Flow extensions).
    ///
    ///   register()                                             = 0x1aa3a008
    ///   register(string)                                       = 0xf2c298be
    ///   register(string,(string,bytes)[])                      = 0x will be computed
    ///   setAgentURI(uint256,string)                            = computed
    ///   getMetadata(uint256,string)                            = computed
    ///   setMetadata(uint256,string,bytes)                      = computed
    ///   setAgentWallet(uint256,address,uint256,bytes)          = computed
    ///   getAgentWallet(uint256)                                = computed
    ///   unsetAgentWallet(uint256)                              = computed
    bytes4 public constant ERC8004_INTERFACE_ID =
        bytes4(keccak256("register()")) ^
        bytes4(keccak256("register(string)")) ^
        bytes4(keccak256("register(string,(string,bytes)[])")) ^
        bytes4(keccak256("setAgentURI(uint256,string)")) ^
        bytes4(keccak256("getMetadata(uint256,string)")) ^
        bytes4(keccak256("setMetadata(uint256,string,bytes)")) ^
        bytes4(keccak256("setAgentWallet(uint256,address,uint256,bytes)")) ^
        bytes4(keccak256("getAgentWallet(uint256)")) ^
        bytes4(keccak256("unsetAgentWallet(uint256)"));

    /// @notice Legacy interface ID from V1 (kept for backward compatibility)
    bytes4 public constant LEGACY_INTERFACE_ID = 0x4f9a2e72;

    /// @dev EIP-712 typehash for setAgentWallet signature verification
    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");

    /// @dev ERC-1271 magic value
    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;

    /// @dev Maximum deadline delay for setAgentWallet signatures
    uint256 private constant MAX_DEADLINE_DELAY = 5 minutes;

    /// @dev Reserved metadata key hash for agentWallet (cannot be set via setMetadata)
    bytes32 private constant RESERVED_AGENT_WALLET_KEY_HASH = keccak256("agentWallet");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Counter for token IDs (starts at 1, 0 = "no token")
    uint256 private _nextTokenId;

    // FLOW-EXTENSION: one-token-per-address mapping for COA identity model
    /// @notice Maps owner address -> token ID (0 means no token)
    mapping(address => uint256) private _ownerToToken;

    // FLOW-EXTENSION: identity records with agentType and active status
    /// @notice Full identity records per token ID
    mapping(uint256 => AgentIdentity) private _identities;

    /// @notice Key-value metadata store per token ID (ERC-8004 string keys)
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(address initialOwner)
        ERC721("FlowIntents Agent Identity", "FIAI")
        Ownable(initialOwner)
        EIP712("ERC8004IdentityRegistry", "1")
    {
        _nextTokenId = 1; // start IDs at 1 so 0 can mean "not registered"
    }

    // =========================================================================
    // ERC-8004 Standard: Registration
    // =========================================================================

    /// @inheritdoc IAgentIdentityRegistry
    function register() external override returns (uint256 agentId) {
        // FLOW-EXTENSION: one-per-address enforcement
        require(
            _ownerToToken[msg.sender] == 0,
            "AgentIdentityRegistry: address already registered"
        );

        agentId = _nextTokenId;
        unchecked { _nextTokenId++; }

        _safeMint(msg.sender, agentId);

        // Set default agentWallet to msg.sender (ERC-8004 standard behavior)
        _metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);

        // FLOW-EXTENSION: populate identity record
        _identities[agentId] = AgentIdentity({
            tokenId: agentId,
            owner: msg.sender,
            agentType: bytes32(0),
            metadataURI: "",
            registeredAt: block.timestamp,
            active: true
        });
        _ownerToToken[msg.sender] = agentId;

        emit Registered(agentId, "", msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));
    }

    /// @inheritdoc IAgentIdentityRegistry
    function register(string calldata agentURI) external override returns (uint256 agentId) {
        // FLOW-EXTENSION: one-per-address enforcement
        require(
            _ownerToToken[msg.sender] == 0,
            "AgentIdentityRegistry: address already registered"
        );

        agentId = _nextTokenId;
        unchecked { _nextTokenId++; }

        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);

        // Set default agentWallet to msg.sender (ERC-8004 standard behavior)
        _metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);

        // FLOW-EXTENSION: populate identity record
        _identities[agentId] = AgentIdentity({
            tokenId: agentId,
            owner: msg.sender,
            agentType: bytes32(0),
            metadataURI: agentURI,
            registeredAt: block.timestamp,
            active: true
        });
        _ownerToToken[msg.sender] = agentId;

        emit Registered(agentId, agentURI, msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));
    }

    /// @inheritdoc IAgentIdentityRegistry
    function register(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        override
        returns (uint256 agentId)
    {
        // FLOW-EXTENSION: one-per-address enforcement
        require(
            _ownerToToken[msg.sender] == 0,
            "AgentIdentityRegistry: address already registered"
        );

        agentId = _nextTokenId;
        unchecked { _nextTokenId++; }

        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);

        // Set default agentWallet to msg.sender (ERC-8004 standard behavior)
        _metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);

        // FLOW-EXTENSION: populate identity record
        _identities[agentId] = AgentIdentity({
            tokenId: agentId,
            owner: msg.sender,
            agentType: bytes32(0),
            metadataURI: agentURI,
            registeredAt: block.timestamp,
            active: true
        });
        _ownerToToken[msg.sender] = agentId;

        emit Registered(agentId, agentURI, msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));

        // Process additional metadata entries
        for (uint256 i; i < metadata.length; i++) {
            require(
                keccak256(bytes(metadata[i].metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH,
                "AgentIdentityRegistry: reserved key"
            );
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }
    }

    // =========================================================================
    // ERC-8004 Standard: URI Management
    // =========================================================================

    /// @inheritdoc IAgentIdentityRegistry
    function setAgentURI(uint256 agentId, string calldata newURI) external override {
        require(
            ownerOf(agentId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        _setTokenURI(agentId, newURI);
        // FLOW-EXTENSION: keep identity record in sync
        _identities[agentId].metadataURI = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
        // FLOW-EXTENSION: also emit legacy event for backward compat
        emit AgentURIUpdated(agentId, newURI);
    }

    // =========================================================================
    // ERC-8004 Standard: Metadata
    // =========================================================================

    /// @inheritdoc IAgentIdentityRegistry
    function getMetadata(uint256 agentId, string memory metadataKey)
        external
        view
        override
        returns (bytes memory)
    {
        return _metadata[agentId][metadataKey];
    }

    /// @inheritdoc IAgentIdentityRegistry
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue)
        external
        override
    {
        require(
            ownerOf(agentId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(
            keccak256(bytes(metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH,
            "AgentIdentityRegistry: reserved key"
        );
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    // =========================================================================
    // ERC-8004 Standard: Agent Wallet
    // =========================================================================

    /// @inheritdoc IAgentIdentityRegistry
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external override {
        require(
            ownerOf(agentId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        require(newWallet != address(0), "AgentIdentityRegistry: zero wallet");
        require(block.timestamp <= deadline, "AgentIdentityRegistry: expired");
        require(deadline <= block.timestamp + MAX_DEADLINE_DELAY, "AgentIdentityRegistry: deadline too far");

        // EIP-712 signature verification
        bytes32 structHash = keccak256(
            abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, msg.sender, deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // Try ECDSA first (EOAs + EIP-7702 delegated EOAs)
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered != newWallet) {
            // ECDSA failed, try ERC-1271 (smart contract wallets / COAs)
            (bool ok, bytes memory res) = newWallet.staticcall(
                abi.encodeCall(IERC1271.isValidSignature, (digest, signature))
            );
            require(
                ok && res.length >= 32 && abi.decode(res, (bytes4)) == ERC1271_MAGICVALUE,
                "AgentIdentityRegistry: invalid wallet sig"
            );
        }

        _metadata[agentId]["agentWallet"] = abi.encodePacked(newWallet);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));
    }

    /// @inheritdoc IAgentIdentityRegistry
    function getAgentWallet(uint256 agentId)
        external
        view
        override
        returns (address)
    {
        bytes memory walletData = _metadata[agentId]["agentWallet"];
        if (walletData.length == 0) return address(0);
        return address(bytes20(walletData));
    }

    /// @inheritdoc IAgentIdentityRegistry
    function unsetAgentWallet(uint256 agentId) external override {
        require(
            ownerOf(agentId) == msg.sender,
            "AgentIdentityRegistry: not token owner"
        );
        _metadata[agentId]["agentWallet"] = "";
        emit MetadataSet(agentId, "agentWallet", "agentWallet", "");
    }

    // =========================================================================
    // FLOW-EXTENSION: Legacy registerAgent() alias
    // =========================================================================

    /// @inheritdoc IAgentIdentityRegistry
    /// @dev Backward-compatible registration with agentType. Enforces one-per-address.
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

        // Set default agentWallet to msg.sender (ERC-8004 standard behavior)
        _metadata[tokenId]["agentWallet"] = abi.encodePacked(msg.sender);

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
        emit Registered(tokenId, metadataURI, msg.sender);
        emit MetadataSet(tokenId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));
    }

    // =========================================================================
    // FLOW-EXTENSION: Identity queries for COA staticCall
    // =========================================================================

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

    // =========================================================================
    // FLOW-EXTENSION: Lifecycle management
    // =========================================================================

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

    // =========================================================================
    // ERC-165
    // =========================================================================

    /// @notice Supports ERC-721, ERC-721Metadata, ERC-165, ERC-8004, and legacy interface
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

    // =========================================================================
    // Transfer hooks — update _ownerToToken on transfer + clear agentWallet
    // =========================================================================

    /// @dev Override _update to maintain ownerToToken mapping and clear agentWallet
    ///      on transfers (ERC-8004 standard behavior: wallet doesn't persist to new owner)
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // ERC-8004 standard: clear agentWallet on transfer (not mint/burn)
        if (from != address(0) && to != address(0)) {
            _metadata[tokenId]["agentWallet"] = "";
            emit MetadataSet(tokenId, "agentWallet", "agentWallet", "");
        }

        address previousOwner = super._update(to, tokenId, auth);

        // FLOW-EXTENSION: maintain one-per-address mapping
        if (from != address(0)) {
            delete _ownerToToken[from];
        }

        if (to != address(0)) {
            require(
                _ownerToToken[to] == 0,
                "AgentIdentityRegistry: destination already has a token"
            );
            _ownerToToken[to] = tokenId;
            // FLOW-EXTENSION: update stored owner in identity record
            _identities[tokenId].owner = to;
        }

        return previousOwner;
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _existsToken(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
