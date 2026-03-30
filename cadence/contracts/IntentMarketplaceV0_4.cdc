/// IntentMarketplaceV0_4.cdc
/// V0_4 Intent Marketplace — User-Executed Intent Model.
///
/// Key differences from V0_3:
///   - User does NOT deposit principal at intent creation — principal stays in wallet
///   - Only commission escrow (small FLOW amount) is deposited
///   - User specifies `tokenOut` (EVM address of desired output token)
///   - User specifies `deliverySide` and optional `deliveryAddress`
///   - After solver wins, the USER signs and executes the transaction
///
/// IMPORTANT: This is a NEW contract — does NOT modify V0_3.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"

access(all) contract IntentMarketplaceV0_4 {

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    access(all) enum IntentStatus: UInt8 {
        access(all) case Open        // 0 — accepting bids
        access(all) case BidSelected // 1 — winner chosen, awaiting user execution
        access(all) case Active      // 2 — strategy executed onchain
        access(all) case Completed   // 3 — intent fulfilled
        access(all) case Cancelled   // 4 — owner cancelled before execution
        access(all) case Expired     // 5 — passed expiryBlock without execution
    }

    access(all) enum IntentType: UInt8 {
        access(all) case Yield       // 0 — maximize yield on Flow
        access(all) case Swap        // 1 — swap token A for token B at best rate
    }

    /// DeliverySide — where the output tokens should be delivered
    access(all) enum DeliverySide: UInt8 {
        access(all) case CadenceVault   // 0 — bridge back to Cadence FungibleToken vault
        access(all) case COA            // 1 — stay in user's COA on EVM
        access(all) case ExternalEVM    // 2 — send to external EVM address
        access(all) case ExternalCadence // 3 — send to another Cadence address
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event IntentCreated(
        id: UInt64,
        owner: Address,
        intentType: UInt8,
        principalAmount: UFix64,
        tokenOut: String,
        deliverySide: UInt8,
        deliveryAddress: String?,
        durationDays: UInt64,
        expiryBlock: UInt64
    )

    access(all) event IntentCancelled(id: UInt64, owner: Address, refundedEscrow: UFix64)
    access(all) event IntentExpired(id: UInt64, owner: Address, refundedEscrow: UFix64)
    access(all) event IntentCompleted(id: UInt64, owner: Address)
    access(all) event IntentExecutionRecorded(id: UInt64, txHash: String, executedAt: UFix64)
    access(all) event CommissionEscrowDeposited(intentID: UInt64, amount: UFix64)
    access(all) event CommissionPaidToSolver(intentID: UInt64, solverAddress: Address, amount: UFix64)
    access(all) event CommissionRefunded(intentID: UInt64, ownerAddress: Address, amount: UFix64)

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
        access(all) let intentType: IntentType

        // ---- Principal declaration (NOT deposited) ----
        access(all) let principalAmount: UFix64    // declared amount the user intends to use

        // ---- Token specification ----
        /// EVM address of the desired output token (e.g. stgUSDC address)
        /// For Yield intents, this may be empty string (yield on same token)
        access(all) let tokenOut: String

        // ---- Delivery routing ----
        access(all) let deliverySide: DeliverySide
        /// Destination address — nil means deliver to self
        /// For ExternalEVM: "0x..." EVM address
        /// For ExternalCadence: Flow address string
        access(all) let deliveryAddress: String?

        // ---- Yield fields ----
        access(all) let targetAPY: UFix64

        // ---- Common timing ----
        access(all) let durationDays: UInt64
        access(all) let expiryBlock: UInt64
        access(all) var status: IntentStatus
        access(all) var winningBidID: UInt64?
        access(all) let createdAt: UFix64

        // ---- Execution tracking ----
        access(all) var executionTxHash: String?
        access(all) var executedAt: UFix64?
        access(all) var executedBy: Address?

        // ---- Commission escrow (only deposit, NOT principal) ----
        access(all) var commissionEscrow: @FlowToken.Vault

        init(
            id: UInt64,
            intentOwner: Address,
            intentType: IntentType,
            principalAmount: UFix64,
            tokenOut: String,
            deliverySide: DeliverySide,
            deliveryAddress: String?,
            targetAPY: UFix64,
            durationDays: UInt64,
            expiryBlock: UInt64,
            createdAt: UFix64,
            commissionEscrowVault: @FlowToken.Vault
        ) {
            self.id = id
            self.intentOwner = intentOwner
            self.intentType = intentType
            self.principalAmount = principalAmount
            self.tokenOut = tokenOut
            self.deliverySide = deliverySide
            self.deliveryAddress = deliveryAddress
            self.targetAPY = targetAPY
            self.durationDays = durationDays
            self.expiryBlock = expiryBlock
            self.status = IntentStatus.Open
            self.winningBidID = nil
            self.createdAt = createdAt
            self.executionTxHash = nil
            self.executedAt = nil
            self.executedBy = nil
            self.commissionEscrow <- commissionEscrowVault
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

        access(contract) fun setCompleted() {
            self.status = IntentStatus.Completed
        }

        access(contract) fun setCancelled() {
            self.status = IntentStatus.Cancelled
        }

        access(contract) fun setExpired() {
            self.status = IntentStatus.Expired
        }

        /// Withdraw the FULL commission escrow (solver receives on execution)
        access(contract) fun withdrawFullCommissionEscrow(): @FlowToken.Vault {
            return <- (self.commissionEscrow.withdraw(amount: self.commissionEscrow.balance) as! @FlowToken.Vault)
        }

        access(contract) fun setExecutedBy(addr: Address) {
            self.executedBy = addr
        }

        access(all) fun getCommissionEscrowBalance(): UFix64 {
            return self.commissionEscrow.balance
        }
    }

    // -------------------------------------------------------------------------
    // Marketplace Resource
    // -------------------------------------------------------------------------

    access(all) resource Marketplace {

        // --- Swap intent creation ---

        access(all) fun createSwapIntent(
            ownerAddress: Address,
            principalAmount: UFix64,
            tokenOut: String,
            deliverySide: UInt8,
            deliveryAddress: String?,
            durationDays: UInt64,
            expiryBlock: UInt64,
            commissionEscrowVault: @FlowToken.Vault
        ): UInt64 {
            pre {
                principalAmount > 0.0:   "Principal amount must be positive"
                tokenOut.length > 0:     "tokenOut address required for Swap intents"
                durationDays > 0:        "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }

            let delivery = IntentMarketplaceV0_4.parseDeliverySide(rawValue: deliverySide)

            // Validate delivery address for external delivery sides
            if delivery == DeliverySide.ExternalEVM || delivery == DeliverySide.ExternalCadence {
                assert(deliveryAddress != nil, message: "deliveryAddress required for external delivery")
            }

            let id = IntentMarketplaceV0_4.totalIntents
            let escrowAmount = commissionEscrowVault.balance
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                intentType: IntentType.Swap,
                principalAmount: principalAmount,
                tokenOut: tokenOut,
                deliverySide: delivery,
                deliveryAddress: deliveryAddress,
                targetAPY: 0.0,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs,
                commissionEscrowVault: <- commissionEscrowVault
            )

            IntentMarketplaceV0_4.intents[id] <-! intent
            IntentMarketplaceV0_4.totalIntents = IntentMarketplaceV0_4.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Swap.rawValue,
                principalAmount: principalAmount,
                tokenOut: tokenOut,
                deliverySide: delivery.rawValue,
                deliveryAddress: deliveryAddress,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            if escrowAmount > 0.0 {
                emit CommissionEscrowDeposited(intentID: id, amount: escrowAmount)
            }

            return id
        }

        // --- Yield intent creation ---

        access(all) fun createYieldIntent(
            ownerAddress: Address,
            principalAmount: UFix64,
            targetAPY: UFix64,
            deliverySide: UInt8,
            deliveryAddress: String?,
            durationDays: UInt64,
            expiryBlock: UInt64,
            commissionEscrowVault: @FlowToken.Vault
        ): UInt64 {
            pre {
                principalAmount > 0.0:   "Principal amount must be positive"
                targetAPY > 0.0:         "Target APY must be positive"
                durationDays > 0:        "Duration must be at least 1 day"
                expiryBlock > getCurrentBlock().height: "Expiry block must be in the future"
            }

            let delivery = IntentMarketplaceV0_4.parseDeliverySide(rawValue: deliverySide)

            if delivery == DeliverySide.ExternalEVM || delivery == DeliverySide.ExternalCadence {
                assert(deliveryAddress != nil, message: "deliveryAddress required for external delivery")
            }

            let id = IntentMarketplaceV0_4.totalIntents
            let escrowAmount = commissionEscrowVault.balance
            let nowSecs = getCurrentBlock().timestamp

            let intent <- create Intent(
                id: id,
                intentOwner: ownerAddress,
                intentType: IntentType.Yield,
                principalAmount: principalAmount,
                tokenOut: "",   // Yield intents: yield on same token
                deliverySide: delivery,
                deliveryAddress: deliveryAddress,
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                createdAt: nowSecs,
                commissionEscrowVault: <- commissionEscrowVault
            )

            IntentMarketplaceV0_4.intents[id] <-! intent
            IntentMarketplaceV0_4.totalIntents = IntentMarketplaceV0_4.totalIntents + 1

            emit IntentCreated(
                id: id,
                owner: ownerAddress,
                intentType: IntentType.Yield.rawValue,
                principalAmount: principalAmount,
                tokenOut: "",
                deliverySide: delivery.rawValue,
                deliveryAddress: deliveryAddress,
                durationDays: durationDays,
                expiryBlock: expiryBlock
            )

            if escrowAmount > 0.0 {
                emit CommissionEscrowDeposited(intentID: id, amount: escrowAmount)
            }

            return id
        }

        // --- Cancel ---

        access(all) fun cancelIntent(
            id: UInt64,
            ownerAddress: Address,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_4.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            assert(intent.intentOwner == ownerAddress, message: "Only the intent owner can cancel")
            assert(
                intent.status == IntentStatus.Open || intent.status == IntentStatus.BidSelected,
                message: "Intent cannot be cancelled in its current status"
            )

            // Return commission escrow to owner
            let escrowReturn <- intent.withdrawFullCommissionEscrow()
            let refundedAmount = escrowReturn.balance
            intent.setCancelled()
            receiver.deposit(from: <- escrowReturn)

            emit IntentCancelled(id: id, owner: ownerAddress, refundedEscrow: refundedAmount)
            if refundedAmount > 0.0 {
                emit CommissionRefunded(intentID: id, ownerAddress: ownerAddress, amount: refundedAmount)
            }
        }

        // --- Expire ---

        access(all) fun expireIntent(
            id: UInt64,
            receiver: &{FungibleToken.Receiver}
        ) {
            pre {
                IntentMarketplaceV0_4.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            assert(
                intent.status == IntentStatus.Open || intent.status == IntentStatus.BidSelected,
                message: "Intent is not in an expirable state"
            )
            assert(
                getCurrentBlock().height >= intent.expiryBlock,
                message: "Intent has not yet expired"
            )

            let escrowReturn <- intent.withdrawFullCommissionEscrow()
            let refundedAmount = escrowReturn.balance
            intent.setExpired()
            receiver.deposit(from: <- escrowReturn)

            emit IntentExpired(id: id, owner: intent.intentOwner, refundedEscrow: refundedAmount)
            if refundedAmount > 0.0 {
                emit CommissionRefunded(intentID: id, ownerAddress: intent.intentOwner, amount: refundedAmount)
            }
        }

        // --- Complete ---

        access(all) fun completeIntent(id: UInt64) {
            pre {
                IntentMarketplaceV0_4.intents[id] != nil: "Intent does not exist"
            }
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            assert(intent.status == IntentStatus.Active, message: "Intent must be Active to complete")
            intent.setCompleted()
            emit IntentCompleted(id: id, owner: intent.intentOwner)
        }

        // --- Privileged functions for BidManager / IntentExecutor ---

        access(all) fun setBidSelectedOnIntent(id: UInt64, bidID: UInt64) {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            intent.setBidSelected(bidID: bidID)
        }

        access(all) fun setActiveOnIntent(id: UInt64) {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            intent.setActive()
        }

        access(all) fun recordExecutionOnIntent(id: UInt64, txHash: String, executedAt: UFix64) {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            intent.recordExecution(txHash: txHash, executedAt: executedAt)
            emit IntentExecutionRecorded(id: id, txHash: txHash, executedAt: executedAt)
        }

        access(all) fun setExecutedByOnIntent(id: UInt64, executorAddress: Address) {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            intent.setExecutedBy(addr: executorAddress)
        }

        /// Withdraw the FULL commission escrow — paid to solver after execution
        access(all) fun withdrawFullCommissionEscrowFromIntent(id: UInt64): @FlowToken.Vault {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            return <- intent.withdrawFullCommissionEscrow()
        }

        access(all) fun getCommissionEscrowBalance(id: UInt64): UFix64 {
            let intent = (&IntentMarketplaceV0_4.intents[id] as &Intent?)!
            return intent.getCommissionEscrowBalance()
        }
    }

    // -------------------------------------------------------------------------
    // Helper: parse DeliverySide from raw UInt8
    // -------------------------------------------------------------------------

    access(all) fun parseDeliverySide(rawValue: UInt8): DeliverySide {
        switch rawValue {
            case 0: return DeliverySide.CadenceVault
            case 1: return DeliverySide.COA
            case 2: return DeliverySide.ExternalEVM
            case 3: return DeliverySide.ExternalCadence
        }
        panic("Invalid DeliverySide raw value: ".concat(rawValue.toString()))
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

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.totalIntents = 0
        self.intents <- {}
        self.MarketplaceStoragePath = /storage/FlowIntentsMarketplaceV4
        self.MarketplacePublicPath  = /public/FlowIntentsMarketplaceV4
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
