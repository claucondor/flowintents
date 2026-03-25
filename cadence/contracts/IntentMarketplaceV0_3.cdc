/// IntentMarketplaceV0_3.cdc
/// Dual-chain marketplace for FlowIntents protocol.
/// Extends V0_1 with EVM-side intent support: PrincipalSide enum, EVM intent fields,
/// and createEVMIntent() for ScheduledManagerV0_3 to register EVM-originated intents.
///
/// IMPORTANT: New file — does NOT overwrite IntentMarketplaceV0_1.cdc.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"

access(all) contract IntentMarketplaceV0_3 {

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

    access(all) enum IntentType: UInt8 {
        access(all) case Yield       // 0 — maximize yield on Flow
        access(all) case Swap        // 1 — swap token A for token B at best rate
        access(all) case BridgeYield // 2 — bridge to another chain and earn yield there
    }

    /// PrincipalSide — where the principal originates
    access(all) enum PrincipalSide: UInt8 {
        access(all) case cadence     // 0 — funds deposited on Cadence side
        access(all) case evm         // 1 — funds deposited on EVM side (FlowIntentsComposerV2)
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event IntentCreated(
        id: UInt64,
        owner: Address,
        intentType: UInt8,
        tokenType: String,
        principalAmount: UFix64,
        targetAPY: UFix64,
        durationDays: UInt64,
        expiryBlock: UInt64,
        principalSide: UInt8
    )

    access(all) event EVMIntentCreated(
        id: UInt64,
        evmIntentId: UInt256,
        evmToken: String,
        evmAmount: UInt256,
        principalSide: UInt8
    )

    access(all) event IntentCancelled(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentExpired(id: UInt64, owner: Address, returnedAmount: UFix64)
    access(all) event IntentCompleted(id: UInt64, owner: Address, finalAmount: UFix64)
    access(all) event IntentExecutionRecorded(id: UInt64, txHash: String, executedAt: UFix64)

    // ---- Gas escrow events ----
    access(all) event GasEscrowDeposited(intentID: UInt64, amount: UFix64)
    access(all) event GasEscrowPaidToSolver(intentID: UInt64, solverAddress: Address, amount: UFix64)
    access(all) event GasEscrowRefunded(intentID: UInt64, ownerAddress: Address, amount: UFix64)
    access(all) event FallbackExecutionTriggered(intentID: UInt64, escrowTaken: UFix64)

    // -------------------------------------------------------------------------
    // Contract-level storage
    // -------------------------------------------------------------------------

    access(all) var totalIntents: UInt64
    access(contract) var intents: @{UInt64: Intent}

    access(all) let MarketplaceStoragePath: StoragePath
    access(all) let MarketplacePublicPath:  PublicPath

    access(all) let deployerAddress: Address

    // -------------------------------------------------------------------------
    // Intent Resource
    // -------------------------------------------------------------------------

    access(all) resource Intent {
        access(all) let id: UInt64
        access(all) let intentOwner: Address
        access(all) var principalVault: @{FungibleToken.Vault}
        access(all) let tokenType: Type
        access(all) let principalAmount: UFix64
        access(all) let intentType: IntentType

        // ---- Yield / BridgeYield fields ----
        access(all) let targetAPY: UFix64

        // ---- Swap fields ----
        access(all) let minAmountOut: UFix64?
        access(all) let maxFeeBPS: UInt64?

        // ---- BridgeYield fields ----
        access(all) let minAPY: UFix64?
        access(all) let allowedChains: [String]?

        // ---- Common ----
        access(all) let durationDays: UInt64
        access(all) let expiryBlock: UInt64
        access(all) var status: IntentStatus
        access(all) var winningBidID: UInt64?
        access(all) let createdAt: UFix64

        // ---- Execution tracking ----
        access(all) var executionTxHash: String?
        access(all) var executedAt: UFix64?

        // ---- V0_3 additions: dual-chain fields ----
        access(all) let principalSide: PrincipalSide
        access(all) let evmIntentId: UInt256?
        access(all) let evmToken: String?
        access(all) let evmAmount: UInt256?

        // ---- Optional EVM recipient ("swap and send" support) ----
        /// If set, output tokens are swept to this EVM address instead of the default
        /// (COA address for cadence-side intents, intent.user for EVM-side intents).
        /// Format: "0x<40 hex chars>" e.g. "0xabc...def"
        access(all) let recipientEVMAddress: String?

        // ---- Gas escrow fields ----
        access(all) var gasEscrow: @FlowToken.Vault    // deposited by user at intent creation
        access(all) let executionDeadlineBlock: UInt64  // current block + N (e.g. 1000 blocks)
        access(all) var executedBy: Address?            // who executed (solver or scheduler)

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
            createdAt: UFix64,
            principalSide: PrincipalSide,
            evmIntentId: UInt256?,
            evmToken: String?,
            evmAmount: UInt256?,
            recipientEVMAddress: String?,
            gasEscrowVault: @FlowToken.Vault,
            executionDeadlineBlock: UInt64
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
            self.principalSide = principalSide
            self.evmIntentId = evmIntentId
            self.evmToken = evmToken
            self.evmAmount = evmAmount
            self.recipientEVMAddress = recipientEVMAddress
            self.gasEscrow <- gasEscrowVault
            self.executionDeadlineBlock = executionDeadlineBlock
            self.executedBy = nil
        }

        access(contract) fun setBidSelected(bidID: UInt64) {
            pre { self.status == IntentStatus.Open: "Intent must be Open to select bid" }
            self.status = IntentStatus.BidSelected
            self.winningBidID = bidID
        }

        access(contract) fun setActive() {
            pre { self.status == IntentStatus.BidSelected: "Intent must be BidSelected to become Active" }
            self.status = IntentStatus.Active
        }

        access(contract) fun recordExecution(txHash: String, executedAt: UFix64) {
            self.executionTxHash = txHash
            self.executedAt = executedAt
        }

        access(contract) fun withdrawPrincipal(): @{FungibleToken.Vault} {
            let empty <- self.principalVault.withdraw(amount: self.principalVault.balance)
            return <- empty
        }

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

        // ---- Gas escrow methods ----

        /// Withdraw the FULL gas escrow (solver keeps entire escrow on execution)
        access(contract) fun withdrawFullGasEscrow(): @FlowToken.Vault {
            return <- (self.gasEscrow.withdraw(amount: self.gasEscrow.balance) as! @FlowToken.Vault)
        }

        /// Set who executed this intent
        access(contract) fun setExecutedBy(addr: Address) {
            self.executedBy = addr
        }

        /// Get current gas escrow balance
        access(all) fun getGasEscrowBalance(): UFix64 {
            return self.gasEscrow.balance
        }
    }

    // -------------------------------------------------------------------------
    // Marketplace Resource
    // -------------------------------------------------------------------------

    access(all) resource Marketplace {

        // --- Cadence-side intent creation (same as V0_1) ---

        access(all) fun createYieldIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64,
            gasEscrowVault: @FlowToken.Vault,
            recipientEVMAddress: String?
        ): UInt64 {
            pre {
                vault.balance > 0.0:   "Principal vault cannot be empty"
                targetAPY > 0.0:       "Target APY must be positive"
                durationDays > 0:      "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_3.totalIntents
            let amount = vault.balance
            let gasAmount = gasEscrowVault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp
            // Execution deadline: 1000 blocks after intent creation
            let deadlineBlock = getCurrentBlock().height + 1000

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
                createdAt: nowSecs,
                principalSide: PrincipalSide.cadence,
                evmIntentId: nil,
                evmToken: nil,
                evmAmount: nil,
                recipientEVMAddress: recipientEVMAddress,
                gasEscrowVault: <- gasEscrowVault,
                executionDeadlineBlock: deadlineBlock
            )

            IntentMarketplaceV0_3.intents[id] <-! intent
            IntentMarketplaceV0_3.totalIntents = IntentMarketplaceV0_3.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Yield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                principalSide: PrincipalSide.cadence.rawValue
            )

            if gasAmount > 0.0 {
                emit GasEscrowDeposited(intentID: id, amount: gasAmount)
            }

            return id
        }

        access(all) fun createSwapIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            minAmountOut: UFix64,
            maxFeeBPS: UInt64,
            durationDays: UInt64,
            expiryBlock: UInt64,
            gasEscrowVault: @FlowToken.Vault,
            recipientEVMAddress: String?
        ): UInt64 {
            pre {
                vault.balance > 0.0:   "Principal vault cannot be empty"
                minAmountOut > 0.0:    "minAmountOut must be positive"
                durationDays > 0:      "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_3.totalIntents
            let amount = vault.balance
            let gasAmount = gasEscrowVault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp
            let deadlineBlock = getCurrentBlock().height + 1000

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
                createdAt: nowSecs,
                principalSide: PrincipalSide.cadence,
                evmIntentId: nil,
                evmToken: nil,
                evmAmount: nil,
                recipientEVMAddress: recipientEVMAddress,
                gasEscrowVault: <- gasEscrowVault,
                executionDeadlineBlock: deadlineBlock
            )

            IntentMarketplaceV0_3.intents[id] <-! intent
            IntentMarketplaceV0_3.totalIntents = IntentMarketplaceV0_3.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Swap.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: 0.0,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                principalSide: PrincipalSide.cadence.rawValue
            )

            if gasAmount > 0.0 {
                emit GasEscrowDeposited(intentID: id, amount: gasAmount)
            }

            return id
        }

        access(all) fun createBridgeYieldIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            minAPY: UFix64,
            allowedChains: [String],
            durationDays: UInt64,
            expiryBlock: UInt64,
            gasEscrowVault: @FlowToken.Vault,
            recipientEVMAddress: String?
        ): UInt64 {
            pre {
                vault.balance > 0.0:      "Principal vault cannot be empty"
                minAPY > 0.0:             "minAPY must be positive"
                allowedChains.length > 0: "Must specify at least one allowed chain"
                durationDays > 0:         "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_3.totalIntents
            let amount = vault.balance
            let gasAmount = gasEscrowVault.balance
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp
            let deadlineBlock = getCurrentBlock().height + 1000

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
                createdAt: nowSecs,
                principalSide: PrincipalSide.cadence,
                evmIntentId: nil,
                evmToken: nil,
                evmAmount: nil,
                recipientEVMAddress: recipientEVMAddress,
                gasEscrowVault: <- gasEscrowVault,
                executionDeadlineBlock: deadlineBlock
            )

            IntentMarketplaceV0_3.intents[id] <-! intent
            IntentMarketplaceV0_3.totalIntents = IntentMarketplaceV0_3.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.BridgeYield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: amount,
                targetAPY: minAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                principalSide: PrincipalSide.cadence.rawValue
            )

            if gasAmount > 0.0 {
                emit GasEscrowDeposited(intentID: id, amount: gasAmount)
            }

            return id
        }

        /// Generic create (backward compat — defaults to Yield, cadence side, no custom recipient).
        access(all) fun createIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64,
            gasEscrowVault: @FlowToken.Vault
        ): UInt64 {
            return self.createYieldIntent(
                ownerAddress: ownerAddress,
                vault: <- vault,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                gasEscrowVault: <- gasEscrowVault,
                recipientEVMAddress: nil
            )
        }

        // --- V0_2 addition: EVM-side intent creation ---

        /// Create an intent originating from the EVM side (FlowIntentsComposerV2).
        /// Called by ScheduledManagerV0_2 after polling getPendingIntents().
        /// A zero-balance vault is used as placeholder since funds live on EVM.
        access(all) fun createEVMIntent(
            ownerAddress: Address,
            vault: @{FungibleToken.Vault},
            evmIntentId: UInt256,
            evmToken: String,
            evmAmount: UInt256,
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64
        ): UInt64 {
            pre {
                evmAmount > 0:        "EVM amount must be positive"
                targetAPY > 0.0:      "Target APY must be positive"
                durationDays > 0:     "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }
            let id = IntentMarketplaceV0_3.totalIntents
            let tokenTypeStr = vault.getType().identifier
            let nowSecs = getCurrentBlock().timestamp
            // EVM intents get zero gas escrow (gas handled on EVM side)
            let emptyGasVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            let deadlineBlock = getCurrentBlock().height + 1000

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
                createdAt: nowSecs,
                principalSide: PrincipalSide.evm,
                evmIntentId: evmIntentId,
                evmToken: evmToken,
                evmAmount: evmAmount,
                recipientEVMAddress: nil,
                gasEscrowVault: <- emptyGasVault,
                executionDeadlineBlock: deadlineBlock
            )

            IntentMarketplaceV0_3.intents[id] <-! intent
            IntentMarketplaceV0_3.totalIntents = IntentMarketplaceV0_3.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Yield.rawValue,
                tokenType: tokenTypeStr,
                principalAmount: 0.0,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                principalSide: PrincipalSide.evm.rawValue
            )

            emit EVMIntentCreated(
                id: id,
                evmIntentId: evmIntentId,
                evmToken: evmToken,
                evmAmount: evmAmount,
                principalSide: PrincipalSide.evm.rawValue
            )

            return id
        }

        // --- Cancel / Expire / Complete ---

        access(all) fun cancelIntent(
            id: UInt64,
            ownerAddress: Address,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_3.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            assert(intent.intentOwner == ownerAddress, message: "Only the intent owner can cancel")
            assert(
                intent.status == IntentStatus.Open || intent.status == IntentStatus.BidSelected,
                message: "Intent cannot be cancelled in its current status"
            )

            let returnVault <- intent.withdrawPrincipal()
            let returnedAmount = returnVault.balance
            // Also return gas escrow on cancel
            let gasReturn <- intent.withdrawFullGasEscrow()
            let gasReturnedAmount = gasReturn.balance
            intent.setCancelled()
            receiver.deposit(from: <- returnVault)
            // Gas escrow is FlowToken, deposit to same receiver
            receiver.deposit(from: <- gasReturn)

            emit IntentCancelled(id: id, owner: ownerAddress, returnedAmount: returnedAmount)
            if gasReturnedAmount > 0.0 {
                emit GasEscrowRefunded(intentID: id, ownerAddress: ownerAddress, amount: gasReturnedAmount)
            }
        }

        access(all) fun expireIntent(
            id: UInt64,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_3.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
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
            let gasReturn <- intent.withdrawFullGasEscrow()
            let gasReturnedAmount = gasReturn.balance
            intent.setExpired()
            receiver.deposit(from: <- returnVault)
            receiver.deposit(from: <- gasReturn)

            emit IntentExpired(id: id, owner: intent.intentOwner, returnedAmount: returnedAmount)
            if gasReturnedAmount > 0.0 {
                emit GasEscrowRefunded(intentID: id, ownerAddress: intent.intentOwner, amount: gasReturnedAmount)
            }
        }

        access(all) fun completeIntent(
            id: UInt64,
            returnVault: @{FungibleToken.Vault},
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_3.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            assert(intent.status == IntentStatus.Active, message: "Intent must be Active to complete")

            let finalAmount = returnVault.balance
            intent.setCompleted()
            receiver.deposit(from: <- returnVault)

            emit IntentCompleted(id: id, owner: intent.intentOwner, finalAmount: finalAmount)
        }

        // --- Privileged functions for BidManager / IntentExecutor ---

        access(all) fun setBidSelectedOnIntent(id: UInt64, bidID: UInt64) {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            intent.setBidSelected(bidID: bidID)
        }

        access(all) fun setActiveOnIntent(id: UInt64) {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            intent.setActive()
        }

        access(all) fun recordExecutionOnIntent(id: UInt64, txHash: String, executedAt: UFix64) {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            intent.recordExecution(txHash: txHash, executedAt: executedAt)
            emit IntentExecutionRecorded(id: id, txHash: txHash, executedAt: executedAt)
        }

        access(all) fun withdrawPrincipalFromIntent(id: UInt64): @{FungibleToken.Vault} {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            return <- intent.withdrawPrincipal()
        }

        access(all) fun depositPrincipalToIntent(id: UInt64, vault: @{FungibleToken.Vault}) {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            intent.depositPrincipal(vault: <- vault)
        }

        // --- Gas escrow operations (called by IntentExecutor / ScheduledManager) ---

        /// Withdraw the FULL gas escrow — solver keeps entire escrow on execution
        access(all) fun withdrawFullGasEscrowFromIntent(id: UInt64): @FlowToken.Vault {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            return <- intent.withdrawFullGasEscrow()
        }

        /// Mark who executed the intent
        access(all) fun setExecutedByOnIntent(id: UInt64, executorAddress: Address) {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            intent.setExecutedBy(addr: executorAddress)
        }

        /// Get the execution deadline block for an intent
        access(all) fun getExecutionDeadlineBlock(id: UInt64): UInt64 {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            return intent.executionDeadlineBlock
        }

        /// Get gas escrow balance for an intent
        access(all) fun getGasEscrowBalance(id: UInt64): UFix64 {
            let intent = (&IntentMarketplaceV0_3.intents[id] as &Intent?)!
            return intent.getGasEscrowBalance()
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

    /// Get all intents with BidSelected status (for fallback execution checks)
    access(all) fun getBidSelectedIntents(): [UInt64] {
        let ids: [UInt64] = []
        var i: UInt64 = 0
        while i < self.totalIntents {
            if let intent = self.getIntent(id: i) {
                if intent.status == IntentStatus.BidSelected {
                    ids.append(i)
                }
            }
            i = i + 1
        }
        return ids
    }

    /// Get all EVM-originated intents (principalSide == evm)
    access(all) fun getEVMIntents(): [UInt64] {
        let ids: [UInt64] = []
        var i: UInt64 = 0
        while i < self.totalIntents {
            if let intent = self.getIntent(id: i) {
                if intent.principalSide == PrincipalSide.evm {
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
        self.MarketplaceStoragePath = /storage/FlowIntentsMarketplaceV3
        self.MarketplacePublicPath  = /public/FlowIntentsMarketplaceV3
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
