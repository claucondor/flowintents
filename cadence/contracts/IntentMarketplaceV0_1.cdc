/// IntentMarketplaceV0_1.cdc
/// Core marketplace contract for FlowIntents protocol.
/// Users deposit funds into an Intent resource vault; AI agent solvers compete to execute yield strategies.
///
/// IMPORTANT: All resource fields are immutable after first deploy.
/// Optionals added here for future extensibility — do not remove them.

import FungibleToken from "FungibleToken"

access(all) contract IntentMarketplaceV0_1 {

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    access(all) enum IntentStatus: UInt8 {
        access(all) case Open        // 0 — accepting bids
        access(all) case BidSelected // 1 — winner chosen, awaiting execution
        access(all) case Active      // 2 — strategy running onchain
        access(all) case Completed   // 3 — funds returned, intent fulfilled
        access(all) case Cancelled   // 4 — owner cancelled before execution
        access(all) case Expired     // 5 — passed expiryBlock without execution
    }

    /// IntentType — which kind of operation the user wants.
    access(all) enum IntentType: UInt8 {
        access(all) case Yield       // 0 — maximize yield on Flow
        access(all) case Swap        // 1 — swap token A for token B at best rate
        access(all) case BridgeYield // 2 — bridge to another chain and earn yield there
    }

    // -------------------------------------------------------------------------
    // Events (exact names — do not rename)
    // -------------------------------------------------------------------------

    access(all) event IntentCreated(
        id: UInt64,
        owner: Address,
        intentType: UInt8,
        tokenType: String,
        principalAmount: UFix64,
        targetAPY: UFix64,
        durationDays: UInt64,
        expiryBlock: UInt64
    )

    access(all) event IntentCancelled(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentExpired(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentCompleted(id: UInt64, owner: Address, finalAmount: UFix64)
    access(all) event IntentExecutionRecorded(id: UInt64, txHash: String, executedAt: UFix64)

    // -------------------------------------------------------------------------
    // Contract-level storage
    // -------------------------------------------------------------------------

    access(all) var totalIntents: UInt64
    access(contract) var intents: @{UInt64: Intent}

    // Canonical storage / public paths
    access(all) let MarketplaceStoragePath: StoragePath
    access(all) let MarketplacePublicPath:  PublicPath

    /// The address of the account that deployed this contract.
    /// Exposed so transactions can locate the Marketplace public capability
    /// without needing to access the restricted `self.account` field.
    access(all) let deployerAddress: Address

    // -------------------------------------------------------------------------
    // Intent Resource
    // -------------------------------------------------------------------------

    access(all) resource Intent {
        access(all) let id: UInt64
        /// intentOwner stores the Address of the user who created this intent.
        /// Named `intentOwner` (not `owner`) because `owner` is a reserved
        /// built-in property on all Cadence 1.0 resources (&Account?).
        access(all) let intentOwner: Address
        // Funds live inside the intent, not a separate account
        access(all) var principalVault: @{FungibleToken.Vault}
        access(all) let tokenType: Type
        access(all) let principalAmount: UFix64
        access(all) let intentType: IntentType

        // ---- Yield / BridgeYield fields ----
        access(all) let targetAPY: UFix64      // 0.0 if not a yield intent

        // ---- Swap fields (nil for non-swap intents) ----
        access(all) let minAmountOut: UFix64?  // minimum tokens to receive in swap
        access(all) let maxFeeBPS: UInt64?     // maximum fee in basis points (10000 = 100%)

        // ---- BridgeYield fields (nil for non-bridge intents) ----
        access(all) let minAPY: UFix64?        // minimum acceptable APY on target chain
        access(all) let allowedChains: [String]? // e.g. ["ethereum", "base", "arbitrum"]

        // ---- Common ----
        access(all) let durationDays: UInt64
        access(all) let expiryBlock: UInt64
        access(all) var status: IntentStatus
        access(all) var winningBidID: UInt64?
        access(all) let createdAt: UFix64

        // ---- Execution tracking (set after execution, for auditability) ----
        access(all) var executionTxHash: String?
        access(all) var executedAt: UFix64?

        init(
            id: UInt64,
            intentOwner: Address,
            vault: @{FungibleToken.Vault},
            intentType: IntentType,
            targetAPY: UFix64,
            minAmountOut: UFix64?,
            maxFeeBPS: UInt64?,
            minAPY: UFix64?,
            allowedChains: [String]?,
            durationDays: UInt64,
            expiryBlock: UInt64,
            createdAt: UFix64
        ) {
            self.id = id
            self.intentOwner = intentOwner
            self.principalAmount = vault.balance
            self.tokenType = vault.getType()
            self.principalVault <- vault
            self.intentType = intentType
            self.targetAPY = targetAPY
            self.minAmountOut = minAmountOut
            self.maxFeeBPS = maxFeeBPS
            self.minAPY = minAPY
            self.allowedChains = allowedChains
            self.durationDays = durationDays
            self.expiryBlock = expiryBlock
            self.status = IntentStatus.Open
            self.winningBidID = nil
            self.createdAt = createdAt
            self.executionTxHash = nil
            self.executedAt = nil
        }

        /// Mark bid selected. Called by BidManager after winner selection.
        access(contract) fun setBidSelected(bidID: UInt64) {
            pre { self.status == IntentStatus.Open: "Intent must be Open to select bid" }
            self.status = IntentStatus.BidSelected
            self.winningBidID = bidID
        }

        /// Mark intent as Active. Called by IntentExecutor after strategy deployed.
        access(contract) fun setActive() {
            pre { self.status == IntentStatus.BidSelected: "Intent must be BidSelected to become Active" }
            self.status = IntentStatus.Active
        }

        /// Record the EVM execution transaction hash and timestamp.
        access(contract) fun recordExecution(txHash: String, executedAt: UFix64) {
            self.executionTxHash = txHash
            self.executedAt = executedAt
        }

        /// Withdraw the full principal vault (for execution, cancellation, expiry).
        access(contract) fun withdrawPrincipal(): @{FungibleToken.Vault} {
            let empty <- self.principalVault.withdraw(amount: self.principalVault.balance)
            return <- empty
        }

        /// Deposit back into the principal vault (returns from EVM, rebalances, etc.).
        access(contract) fun depositPrincipal(vault: @{FungibleToken.Vault}) {
            self.principalVault.deposit(from: <- vault)
        }

        access(contract) fun setCompleted() {
            self.status = IntentStatus.Completed
        }

        access(contract) fun setCancelled() {
            self.status = IntentStatus.Cancelled
        }

        access(contract) fun setExpired() {
            self.status = IntentStatus.Expired
        }
    }

    // -------------------------------------------------------------------------
    // Marketplace Resource (stored in contract account)
    // -------------------------------------------------------------------------

    access(all) resource Marketplace {

        // --- Core factory ---

        /// Create a Yield intent (maximize APY on Flow).
        access(all) fun createYieldIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                vault.balance > 0.0:   "Principal vault cannot be empty"
                targetAPY > 0.0:       "Target APY must be positive"
                durationDays > 0:      "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_1.totalIntents
            let amount = vault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                vault: <- vault,
                intentType: IntentType.Yield,
                targetAPY: targetAPY,
                minAmountOut: nil,
                maxFeeBPS: nil,
                minAPY: nil,
                allowedChains: nil,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs
            )

            IntentMarketplaceV0_1.intents[id] <-! intent
            IntentMarketplaceV0_1.totalIntents = IntentMarketplaceV0_1.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Yield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            return id
        }

        /// Create a Swap intent (token A → token B at best rate).
        access(all) fun createSwapIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            minAmountOut: UFix64,
            maxFeeBPS: UInt64,
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                vault.balance > 0.0:   "Principal vault cannot be empty"
                minAmountOut > 0.0:    "minAmountOut must be positive"
                durationDays > 0:      "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_1.totalIntents
            let amount = vault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                vault: <- vault,
                intentType: IntentType.Swap,
                targetAPY: 0.0,
                minAmountOut: minAmountOut,
                maxFeeBPS: maxFeeBPS,
                minAPY: nil,
                allowedChains: nil,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs
            )

            IntentMarketplaceV0_1.intents[id] <-! intent
            IntentMarketplaceV0_1.totalIntents = IntentMarketplaceV0_1.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Swap.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: 0.0,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            return id
        }

        /// Create a BridgeYield intent (bridge to another chain and earn yield).
        access(all) fun createBridgeYieldIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            minAPY: UFix64,
            allowedChains: [String],
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                vault.balance > 0.0:      "Principal vault cannot be empty"
                minAPY > 0.0:             "minAPY must be positive"
                allowedChains.length > 0: "Must specify at least one allowed chain"
                durationDays > 0:         "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_1.totalIntents
            let amount = vault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                vault: <- vault,
                intentType: IntentType.BridgeYield,
                targetAPY: minAPY,
                minAmountOut: nil,
                maxFeeBPS: nil,
                minAPY: minAPY,
                allowedChains: allowedChains,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs
            )

            IntentMarketplaceV0_1.intents[id] <-! intent
            IntentMarketplaceV0_1.totalIntents = IntentMarketplaceV0_1.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.BridgeYield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: minAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            return id
        }

        /// Generic create (kept for backward compat — defaults to Yield type).
        access(all) fun createIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                vault.balance > 0.0:   "Principal vault cannot be empty"
                targetAPY > 0.0:       "Target APY must be positive"
                durationDays > 0:      "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_1.totalIntents
            let amount = vault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                vault: <- vault,
                intentType: IntentType.Yield,
                targetAPY: targetAPY,
                minAmountOut: nil,
                maxFeeBPS: nil,
                minAPY: nil,
                allowedChains: nil,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs
            )

            IntentMarketplaceV0_1.intents[id] <-! intent
            IntentMarketplaceV0_1.totalIntents = IntentMarketplaceV0_1.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Yield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            return id
        }

        /// Cancel an open intent and return funds to the owner's receiver.
        access(all) fun cancelIntent(
            id: UInt64,
            ownerAddress: Address,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_1.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            assert(intent.intentOwner == ownerAddress, message: "Only the intent owner can cancel")
            assert(
                intent.status == IntentStatus.Open || intent.status == IntentStatus.BidSelected,
                message: "Intent cannot be cancelled in its current status"
            )

            let returnVault <- intent.withdrawPrincipal()
            let returnedAmount = returnVault.balance
            intent.setCancelled()
            receiver.deposit(from: <- returnVault)

            emit IntentCancelled(id: id, owner: ownerAddress, returnedAmount: returnedAmount)
        }

        /// Mark an expired intent and return funds to the owner's receiver.
        access(all) fun expireIntent(
            id: UInt64,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_1.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            assert(
                intent.status == IntentStatus.Open || intent.status == IntentStatus.BidSelected,
                message: "Intent is not in an expirable state"
            )
            assert(
                getCurrentBlock().height >= intent.expiryBlock,
                message: "Intent has not yet expired"
            )

            let returnVault <- intent.withdrawPrincipal()
            let returnedAmount = returnVault.balance
            intent.setExpired()
            receiver.deposit(from: <- returnVault)

            emit IntentExpired(id: id, owner: intent.intentOwner, returnedAmount: returnedAmount)
        }

        /// Called by IntentExecutor to mark completed and return yield-bearing funds.
        access(all) fun completeIntent(
            id: UInt64,
            returnVault: @{FungibleToken.Vault},
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_1.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            assert(intent.status == IntentStatus.Active, message: "Intent must be Active to complete")

            let finalAmount = returnVault.balance
            intent.setCompleted()
            receiver.deposit(from: <- returnVault)

            emit IntentCompleted(id: id, owner: intent.intentOwner, finalAmount: finalAmount)
        }

        // Privileged functions for BidManager / IntentExecutor (accessed via contract functions)
        access(all) fun setBidSelectedOnIntent(id: UInt64, bidID: UInt64) {
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            intent.setBidSelected(bidID: bidID)
        }

        access(all) fun setActiveOnIntent(id: UInt64) {
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            intent.setActive()
        }

        access(all) fun recordExecutionOnIntent(id: UInt64, txHash: String, executedAt: UFix64) {
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            intent.recordExecution(txHash: txHash, executedAt: executedAt)
            emit IntentExecutionRecorded(id: id, txHash: txHash, executedAt: executedAt)
        }

        access(all) fun withdrawPrincipalFromIntent(id: UInt64): @{FungibleToken.Vault} {
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            return <- intent.withdrawPrincipal()
        }

        access(all) fun depositPrincipalToIntent(id: UInt64, vault: @{FungibleToken.Vault}) {
            let intent = (&IntentMarketplaceV0_1.intents[id] as &Intent?)!
            intent.depositPrincipal(vault: <- vault)
        }
    }

    // -------------------------------------------------------------------------
    // Public read functions
    // -------------------------------------------------------------------------

    access(all) fun getIntent(id: UInt64): &Intent? {
        return &self.intents[id] as &Intent?
    }

    access(all) fun getIntentsByUser(owner: Address): [UInt64] {
        let ids: [UInt64] = []
        var i: UInt64 = 0
        while i < self.totalIntents {
            if let intent = self.getIntent(id: i) {
                if intent.intentOwner == owner {
                    ids.append(i)
                }
            }
            i = i + 1
        }
        return ids
    }

    access(all) fun getIntentStatus(id: UInt64): IntentStatus? {
        if let intent = self.getIntent(id: id) {
            return intent.status
        }
        return nil
    }

    access(all) fun getOpenIntents(): [UInt64] {
        let ids: [UInt64] = []
        var i: UInt64 = 0
        while i < self.totalIntents {
            if let intent = self.getIntent(id: i) {
                if intent.status == IntentStatus.Open {
                    ids.append(i)
                }
            }
            i = i + 1
        }
        return ids
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.totalIntents = 0
        self.intents <- {}
        self.MarketplaceStoragePath = /storage/FlowIntentsMarketplace
        self.MarketplacePublicPath  = /public/FlowIntentsMarketplace
        self.deployerAddress = self.account.address

        self.account.storage.save(
            <- create Marketplace(),
            to: self.MarketplaceStoragePath
        )
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<&Marketplace>(self.MarketplaceStoragePath),
            at: self.MarketplacePublicPath
        )
    }
}
