# FlowIntents: ERC-8004 Hybrid + Cadence Selector Registry Plan

## A) ERC-8004 Modifications for Flow Cross-VM (COA Pattern)

### Current State

`AgentIdentityRegistry.sol` implements:
- `registerAgent(bytes32 agentType, string metadataURI)` -> returns tokenId
- `getIdentity(uint256 tokenId)` -> returns AgentIdentity struct
- `getTokenByOwner(address owner)` -> returns tokenId
- `isActive(uint256 tokenId)` -> returns bool
- `setAgentURI(uint256 tokenId, string newURI)`
- `deactivate(uint256 tokenId)` / `activate(uint256 tokenId)`
- `ERC8004_INTERFACE_ID = 0x4f9a2e72`

### Real ERC-8004 Standard Functions

- `register()` (3 overloads)
- `setAgentURI()`
- `setMetadata(key, value)`
- `getMetadata(tokenId, key)`
- `setAgentWallet()` (EIP-712 sig)
- `getAgentWallet()`
- `unsetAgentWallet()`

### Hybrid Design

#### Keep (essential for COA cross-VM calls from Cadence):
1. `getTokenByOwner(address)` -- Cadence SolverRegistry uses this
2. `isActive(uint256)` -- Cadence BidManager uses this
3. `getIdentity(uint256)` -- returns full struct
4. `registerAgent(bytes32, string)` -- backward compat
5. `setAgentURI(uint256, string)` -- already exists
6. `deactivate(uint256)` / `activate(uint256)` -- Flow-specific extensions

#### Add as ERC-8004 standard aliases:
7. `register(bytes32 agentType, string calldata metadataURI)` -- alias for `registerAgent()`
   - Single overload only (keeps it simple for COA context)
8. `setMetadata(uint256 tokenId, bytes32 key, bytes calldata value)` -- key-value store per token
9. `getMetadata(uint256 tokenId, bytes32 key)` -- returns `bytes memory`
10. `setAgentWallet(uint256 tokenId, address wallet)` -- simplified (no EIP-712, owner-only)
11. `getAgentWallet(uint256 tokenId)` -- returns address
12. `unsetAgentWallet(uint256 tokenId)` -- clears wallet

#### New events:
- `event MetadataUpdated(uint256 indexed tokenId, bytes32 indexed key)`
- `event AgentWalletChanged(uint256 indexed tokenId, address indexed wallet)`

#### New storage:
- `mapping(uint256 => mapping(bytes32 => bytes)) private _metadata`
- `mapping(uint256 => address) private _agentWallets`

#### ERC8004_INTERFACE_ID recomputation:
Standard selectors we comply with:
- `register(bytes32,string)` = bytes4(keccak256("register(bytes32,string)"))
- `setAgentURI(uint256,string)` = already have
- `setMetadata(uint256,bytes32,bytes)` = new
- `getMetadata(uint256,bytes32)` = new
- `setAgentWallet(uint256,address)` = simplified (no EIP-712)
- `getAgentWallet(uint256)` = new
- `unsetAgentWallet(uint256)` = new

Non-compliant deviations:
- `setAgentWallet` lacks EIP-712 signature parameter (simplified for COA)
- `register()` has only 1 overload instead of 3
- `activate()`/`deactivate()` are Flow-specific extensions not in standard

The new `ERC8004_INTERFACE_ID` will be XOR of:
```
register(bytes32,string)
setMetadata(uint256,bytes32,bytes)
getMetadata(uint256,bytes32)
setAgentWallet(uint256,address)
getAgentWallet(uint256)
unsetAgentWallet(uint256)
```

#### Interface file changes:
Update `IAgentIdentityRegistry.sol` to add the new function signatures, events, and keep all existing ones.

---

## B) Cadence Selector Registry Pattern

### Concept

Replace all hardcoded EVM addresses and function selectors in Cadence contracts with a configurable registry. This allows changing EVM contract addresses or function selectors via a single admin transaction without redeploying Cadence contracts.

### EVMConfig Struct

```cadence
access(all) struct EVMConfig {
    access(all) let address: String
    access(all) let selector: [UInt8]
    init(address: String, selector: [UInt8]) {
        self.address = address
        self.selector = selector
    }
}
```

### Changes per Contract

#### SolverRegistryV0_1.cdc

**Current hardcoded values:**
- `agentIdentityRegistryAddress` (String) -- EVM address for identity registry
- `agentReputationRegistryAddress` (String) -- EVM address for reputation registry
- Selector `[0x63, 0x52, 0x21, 0x1e]` for `ownerOf(uint256)` (line 134)
- Selector `[0xad, 0xf8, 0x25, 0x2d]` for `getMultiplier(uint256)` (line 152)

**Changes:**
1. Add `access(all) struct EVMConfig { address: String, selector: [UInt8] }`
2. Add `access(self) var evmConfig: {String: EVMConfig}`
3. Admin resource: add `setEVMContract(name: String, config: EVMConfig)`
4. Replace `encodeOwnerOf()` to use `self.evmConfig["identityRegistry_ownerOf"]!.selector`
5. Replace `encodeGetMultiplier()` to use `self.evmConfig["reputationRegistry_getMultiplier"]!.selector`
6. Replace address lookups with `self.evmConfig["identityRegistry_ownerOf"]!.address`
7. In `init()`: populate with default zero addresses and current selectors
8. Keep `agentIdentityRegistryAddress` / `agentReputationRegistryAddress` as computed properties reading from evmConfig for backward compat

**EVMConfig keys (init defaults):**
- `"identityRegistry_ownerOf"` -> address: "0x000...0", selector: [0x63, 0x52, 0x21, 0x1e]
- `"reputationRegistry_getMultiplier"` -> address: "0x000...0", selector: [0xad, 0xf8, 0x25, 0x2d]

#### IntentExecutorV0_1.cdc

**Current hardcoded values:**
- `composerAddress` (String) -- FlowIntentsComposer EVM address
- Placeholder selector `[0x1a, 0x2b, 0x3c, 0x4d]` for `getIntentBalance(uint256)` (line 112)

**Changes:**
1. Add same `EVMConfig` struct
2. Add `access(self) var evmConfig: {String: EVMConfig}`
3. Admin resource: add `setEVMContract(name: String, config: EVMConfig)`
4. Replace `composerAddress` with `self.evmConfig["composer"]!.address`
5. Keep `composerAddress` as computed property for backward compat
6. In `init()`: populate with default zero address

**EVMConfig keys (init defaults):**
- `"composer"` -> address: "0x000...0", selector: [] (batch calls use bid's encodedBatch)
- `"composer_getIntentBalance"` -> address: "0x000...0", selector: [0x1a, 0x2b, 0x3c, 0x4d]

#### BidManagerV0_1.cdc -- NO CHANGES
Does not make any EVM calls. Only reads from Cadence contracts.

#### IntentMarketplaceV0_1.cdc -- NO CHANGES
Does not make any EVM calls. Pure Cadence state management.

### Admin Transaction

Create `cadence/transactions/admin/setEVMContract.cdc`:
- Generic transaction that can update any EVMConfig entry in any contract
- Parameters: `contractName: String, configName: String, evmAddress: String, selector: [UInt8]`
- Routes to correct contract's admin based on `contractName`

---

## C) Implementation Order

1. Update `IAgentIdentityRegistry.sol` with new function signatures
2. Update `AgentIdentityRegistry.sol` with hybrid ERC-8004 implementation
3. Update `SolverRegistryV0_1.cdc` with EVMConfig pattern
4. Update `IntentExecutorV0_1.cdc` with EVMConfig pattern
5. Create `cadence/transactions/admin/setEVMContract.cdc`
6. Update existing admin transactions to work with new pattern
7. Deploy to emulator and verify E2E

---

## D) Backward Compatibility Notes

- All existing function signatures preserved in Solidity (only additions)
- All existing Cadence function signatures preserved
- `agentIdentityRegistryAddress` / `agentReputationRegistryAddress` / `composerAddress` remain accessible
- Existing admin transactions (`setSolverRegistryEVMAddresses.cdc`, `setExecutorComposerAddress.cdc`) continue to work
- New `setEVMContract` transaction is additive
