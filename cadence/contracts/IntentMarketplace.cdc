/// IntentMarketplace.cdc
/// Core marketplace contract for FlowIntents protocol.
/// Users deposit funds into an Intent resource vault; AI agent solvers compete to execute yield strategies.

import FungibleToken from "FungibleToken"

access(all) contract IntentMarketplace {

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

    // -------------------------------------------------------------------------
    // Events (exact names — do not rename)
    // -------------------------------------------------------------------------

    access(all) event IntentCreated(
        id: UInt64,
        owner: Address,
        tokenType: String,
        principalAmount: UFix64,
        targetAPY: UFix64,
        durationDays: UInt64,
        expiryBlock: UInt64
    )

    access(all) event IntentCancelled(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentExpired(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentCompleted(id: UInt64, owner: Address, finalAmount: UFix64)

    // -------------------------------------------------------------------------
    // Contract-level storage
    // -------------------------------------------------------------------------

    access(all) var totalIntents: UInt64
    access(self) var intents: @{UInt64: Intent}

    // Canonical storage / public paths
    access(all) let MarketplaceStoragePath: StoragePath
    access(all) let MarketplacePublicPath:  PublicPath

    // -------------------------------------------------------------------------
    // Intent Resource
    // -------------------------------------------------------------------------

    access(all) resource Intent {
        access(all) let id: UInt64
        access(all) let owner: Address
        // Funds live inside the intent, not a separate account
        access(all) var principalVault: @{FungibleToken.Vault}
        access(all) let tokenType: Type
        access(all) let principalAmount: UFix64
        access(all) let targetAPY: UFix64
        access(all) let durationDays: UInt64
        access(all) let expiryBlock: UInt64
        access(all) var status: IntentStatus
        access(all) var winningBidID: UInt64?
        access(all) let createdAt: UFix64

        init(
            id: UInt64,
            owner: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64,
            createdAt: UFix64
        ) {
            self.id = id
            self.owner = owner
            self.principalAmount = vault.balance
            self.tokenType = vault.getType()
            self.principalVault <- vault
            self.targetAPY = targetAPY
            self.durationDays = durationDays
            self.expiryBlock = expiryBlock
            self.status = IntentStatus.Open
            self.winningBidID = nil
            self.createdAt = createdAt
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

        /// Create a new intent and store it. Returns the new intent ID.
        access(all) fun createIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                vault.balance > 0.0: "Principal vault cannot be empty"
                targetAPY > 0.0: "Target APY must be positive"
                durationDays > 0: "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }

            let id = IntentMarketplace.totalIntents
            let amount = vault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                owner: ownerAddress,
                vault: <- vault,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs
            )

            IntentMarketplace.intents[id] <-! intent
            IntentMarketplace.totalIntents = IntentMarketplace.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
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
                IntentMarketplace.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
            assert(intent.owner == ownerAddress, message: "Only the intent owner can cancel")
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
                IntentMarketplace.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
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

            emit IntentExpired(id: id, owner: intent.owner, returnedAmount: returnedAmount)
        }

        /// Called by IntentExecutor to mark completed and return yield-bearing funds.
        access(all) fun completeIntent(
            id: UInt64,
            returnVault: @{FungibleToken.Vault},
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplace.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
            assert(intent.status == IntentStatus.Active, message: "Intent must be Active to complete")

            let finalAmount = returnVault.balance
            intent.setCompleted()
            receiver.deposit(from: <- returnVault)

            emit IntentCompleted(id: id, owner: intent.owner, finalAmount: finalAmount)
        }

        // Privileged functions for BidManager / IntentExecutor (accessed via contract functions)
        access(all) fun setBidSelectedOnIntent(id: UInt64, bidID: UInt64) {
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
            intent.setBidSelected(bidID: bidID)
        }

        access(all) fun setActiveOnIntent(id: UInt64) {
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
            intent.setActive()
        }

        access(all) fun withdrawPrincipalFromIntent(id: UInt64): @{FungibleToken.Vault} {
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
            return <- intent.withdrawPrincipal()
        }

        access(all) fun depositPrincipalToIntent(id: UInt64, vault: @{FungibleToken.Vault}) {
            let intent = (&IntentMarketplace.intents[id] as &Intent?)!
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
                if intent.owner == owner {
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
