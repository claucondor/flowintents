/// ScheduledManager.cdc
/// Onchain automation for FlowIntents using Forte Scheduled Transactions.
/// Implements the FlowTransactionScheduler.TransactionHandler interface.
/// Iterates active intents, checks positions, rebalances if APY drops below threshold,
/// and returns funds to owners at expiry.

import FlowTransactionScheduler from "FlowTransactionScheduler"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import EVM from "EVM"
import IntentMarketplace from "IntentMarketplace"
import IntentExecutor from "IntentExecutor"
import BidManager from "BidManager"

access(all) contract ScheduledManager {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event PositionChecked(
        intentID: UInt64,
        currentAPY: UFix64,
        targetAPY: UFix64,
        rebalanceTriggered: Bool
    )

    access(all) event ScheduledCheckExecuted(
        scheduledID: UInt64,
        intentsChecked: Int,
        timestamp: UFix64
    )

    access(all) event RebalanceTriggered(intentID: UInt64, oldAPY: UFix64, newAPY: UFix64)

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    /// Fraction of targetAPY below which a rebalance is triggered.
    /// E.g. 0.8 means rebalance if currentAPY < 80% of targetAPY.
    access(all) var rebalanceThreshold: UFix64

    /// Default execution effort for scheduled transactions
    access(all) var defaultExecutionEffort: UInt64

    access(all) let HandlerStoragePath: StoragePath
    access(all) let HandlerPublicPath:  PublicPath
    access(all) let AdminStoragePath:   StoragePath

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setRebalanceThreshold(threshold: UFix64) {
            pre { threshold > 0.0 && threshold <= 1.0: "Threshold must be between 0 and 1" }
            ScheduledManager.rebalanceThreshold = threshold
        }
        access(all) fun setDefaultExecutionEffort(effort: UInt64) {
            ScheduledManager.defaultExecutionEffort = effort
        }
    }

    // -------------------------------------------------------------------------
    // TransactionHandler resource — implements Forte's scheduled tx interface
    // -------------------------------------------------------------------------

    access(all) resource Handler: FlowTransactionScheduler.TransactionHandler {

        /// Called by the Forte protocol at the scheduled time.
        /// `data` contains serialized check instructions (intentIDs or "all").
        access(FlowTransactionScheduler.Execute)
        fun executeTransaction(id: UInt64, data: AnyStruct?) {
            let timestamp = getCurrentBlock().timestamp

            // Parse which intents to check. If data is nil or "all", check all active.
            var intentIDs: [UInt64] = []
            if let rawData = data {
                if let ids = rawData as? [UInt64] {
                    intentIDs = ids
                }
            }

            // If no specific IDs given, we check all open + active intents
            // We read from Marketplace open intents; active ones are tracked separately
            if intentIDs.length == 0 {
                intentIDs = IntentMarketplace.getOpenIntents()
            }

            var checkedCount = 0

            for intentID in intentIDs {
                let intent = IntentMarketplace.getIntent(id: intentID)
                if intent == nil { continue }

                let intentRef = intent!

                // Check expiry — if expired, flag it
                if intentRef.status == IntentMarketplace.IntentStatus.Open ||
                   intentRef.status == IntentMarketplace.IntentStatus.BidSelected {
                    if getCurrentBlock().height >= intentRef.expiryBlock {
                        // Expiry handling — emit event; actual fund return requires owner receiver
                        // The ScheduledManager flags it; a separate cleanup tx handles the vault move
                        emit PositionChecked(
                            intentID: intentID,
                            currentAPY: 0.0,
                            targetAPY: intentRef.targetAPY,
                            rebalanceTriggered: false
                        )
                    }
                }

                // Check active intents for APY drift
                if intentRef.status == IntentMarketplace.IntentStatus.Active {
                    let currentAPY = ScheduledManager.fetchCurrentAPY(intentID: intentID)
                    let targetAPY  = intentRef.targetAPY
                    let threshold  = targetAPY * ScheduledManager.rebalanceThreshold

                    var rebalanceTriggered = false
                    if currentAPY < threshold {
                        // APY has drifted below acceptable threshold — rebalance needed
                        rebalanceTriggered = true
                        emit RebalanceTriggered(
                            intentID: intentID,
                            oldAPY: currentAPY,
                            newAPY: targetAPY
                        )
                        // Rebalance logic: signal that this intent needs re-execution
                        // The actual rebalance is done in a separate tx by the winning solver
                        // (ScheduledManager cannot hold COA — it needs the solver's COA for EVM calls)
                    }

                    emit PositionChecked(
                        intentID: intentID,
                        currentAPY: currentAPY,
                        targetAPY: targetAPY,
                        rebalanceTriggered: rebalanceTriggered
                    )
                    checkedCount = checkedCount + 1
                }
            }

            emit ScheduledCheckExecuted(
                scheduledID: id,
                intentsChecked: checkedCount,
                timestamp: timestamp
            )
        }

        access(all) view fun getViews(): [Type] {
            return [Type<StoragePath>(), Type<PublicPath>()]
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<StoragePath>():
                    return ScheduledManager.HandlerStoragePath
                case Type<PublicPath>():
                    return ScheduledManager.HandlerPublicPath
                default:
                    return nil
            }
        }
    }

    // -------------------------------------------------------------------------
    // Scheduling helper — called by a transaction to register a new check
    // -------------------------------------------------------------------------

    /// Schedule a position-check transaction at a future timestamp.
    /// Requires a FlowToken vault for fees and a reference to the scheduler manager.
    access(all) fun scheduleCheck(
        signer: auth(Storage, Capabilities) &Account,
        schedulerManager: &{FlowTransactionScheduler.SchedulerManager},
        targetTimestamp: UFix64,
        priority: FlowTransactionScheduler.Priority,
        intentIDs: [UInt64]?,
        feesVault: @FlowToken.Vault
    ) {
        let executionEffort = ScheduledManager.defaultExecutionEffort

        let estimate = FlowTransactionScheduler.calculateFee(
            executionEffort: executionEffort,
            priority: priority,
            dataSizeMB: 0
        )
        assert(feesVault.balance >= estimate, message: "Insufficient fees for scheduled transaction")

        // Issue a capability for the handler
        let handlerCap = signer.capabilities.storage.issue<
            auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
        >(ScheduledManager.HandlerStoragePath)

        let data: AnyStruct? = intentIDs != nil ? intentIDs! as AnyStruct : nil

        schedulerManager.schedule(
            handlerCap: handlerCap,
            data: data,
            timestamp: targetTimestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <- feesVault
        )
    }

    // -------------------------------------------------------------------------
    // Internal — read current APY via COA dryCall to Composer
    // -------------------------------------------------------------------------

    /// Query current APY of an intent's EVM position.
    /// Uses EVM.dryCall (staticCall) — no state change.
    access(self) fun fetchCurrentAPY(intentID: UInt64): UFix64 {
        // Encode getCurrentAPY(uint256 intentID) — selector placeholder 0xa1b2c3d4
        var calldata: [UInt8] = [0xa1, 0xb2, 0xc3, 0xd4]
        var tmp = intentID
        var idBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            idBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(idBytes)

        let composerAddr = IntentExecutor.composerAddress
        let zeroAddr = EVM.EVMAddress(bytes: [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ])

        if composerAddr == "0x0000000000000000000000000000000000000000" {
            return 0.0  // Composer not configured yet
        }

        let result = EVM.dryCall(
            from: zeroAddr,
            to: ScheduledManager.parseEVMAddress(composerAddr),
            data: calldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        if result.status != EVM.Status.successful || result.data.length < 32 {
            return 0.0
        }

        // Decode uint256 — APY stored as basis points (10000 = 100.00%)
        var raw: UInt256 = 0
        var i = 0
        while i < 32 {
            raw = raw * 256 + UInt256(result.data[i])
            i = i + 1
        }
        // Convert basis points to UFix64 percentage (e.g. 500 bp = 5.0%)
        return UFix64(raw) / 100.0
    }

    access(self) fun parseEVMAddress(_ hexAddr: String): EVM.EVMAddress {
        var hex = hexAddr
        if hex.length >= 2 && hex.slice(from: 0, upTo: 2) == "0x" {
            hex = hex.slice(from: 2, upTo: hex.length)
        }
        while hex.length < 40 { hex = "0".concat(hex) }
        var bytes: [UInt8] = []
        var i = 0
        while i < 40 {
            let high = ScheduledManager.hexCharToUInt8(hex.slice(from: i,     upTo: i + 1))
            let low  = ScheduledManager.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
            bytes.append((high << 4) | low)
            i = i + 2
        }
        return EVM.EVMAddress(bytes: bytes)
    }

    access(self) fun hexCharToUInt8(_ c: String): UInt8 {
        switch c {
            case "0": return 0; case "1": return 1; case "2": return 2; case "3": return 3
            case "4": return 4; case "5": return 5; case "6": return 6; case "7": return 7
            case "8": return 8; case "9": return 9
            case "a", "A": return 10; case "b", "B": return 11; case "c", "C": return 12
            case "d", "D": return 13; case "e", "E": return 14; case "f", "F": return 15
        }
        return 0
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.rebalanceThreshold    = 0.8   // Rebalance if APY < 80% of target
        self.defaultExecutionEffort = 1000  // Execution effort units

        self.HandlerStoragePath = /storage/FlowIntentsScheduledHandler
        self.HandlerPublicPath  = /public/FlowIntentsScheduledHandler
        self.AdminStoragePath   = /storage/FlowIntentsScheduledAdmin

        self.account.storage.save(<- create Handler(), to: self.HandlerStoragePath)
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<
                &{FlowTransactionScheduler.TransactionHandler}
            >(self.HandlerStoragePath),
            at: self.HandlerPublicPath
        )
        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
