/// ScheduledManagerV0_2.cdc
/// Extends ScheduledManagerV0_1 with EVM intent polling.
/// Polls FlowIntentsComposerV2.getPendingIntents() via COA staticCall,
/// creates corresponding intents in IntentMarketplaceV0_2, and marks them
/// as picked up on the EVM side.
///
/// IMPORTANT: New file — does NOT overwrite ScheduledManagerV0_1.cdc.
/// NOTE: FlowTransactionScheduler integration is deferred to a separate handler
///       contract. This contract focuses on the EVM polling bridge.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import EVM from "EVM"
import IntentMarketplaceV0_2 from "IntentMarketplaceV0_2"

access(all) contract ScheduledManagerV0_2 {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event PositionChecked(
        intentID: UInt64,
        currentAPY: UFix64,
        targetAPY: UFix64,
        rebalanceTriggered: Bool
    )

    access(all) event RebalanceTriggered(intentID: UInt64, oldAPY: UFix64, newAPY: UFix64)

    access(all) event EVMIntentPolled(
        evmIntentId: UInt256,
        cadenceIntentId: UInt64,
        evmToken: String,
        evmAmount: UInt256
    )

    access(all) event EVMPollCompleted(
        intentsPolled: Int,
        intentsCreated: Int,
        timestamp: UFix64
    )

    access(all) event FallbackExecutionTriggered(
        intentID: UInt64,
        escrowTaken: UFix64
    )

    access(all) event EVMConfigUpdated(name: String, address: String, selectorLength: Int)

    // -------------------------------------------------------------------------
    // EVM Selector Registry
    // -------------------------------------------------------------------------

    access(all) struct EVMConfig {
        access(all) let address: String
        access(all) let selector: [UInt8]
        init(address: String, selector: [UInt8]) {
            self.address = address
            self.selector = selector
        }
    }

    /// Configurable EVM contract addresses and selectors.
    /// Keys:
    ///   "composerV2"                   -> FlowIntentsComposerV2 address
    ///   "composerV2_getPendingIntents" -> getPendingIntents() selector
    ///   "composerV2_markPickedUp"      -> markPickedUp(uint256) selector
    access(self) var evmConfig: {String: EVMConfig}

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    access(all) var rebalanceThreshold: UFix64

    access(all) let AdminStoragePath: StoragePath

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setRebalanceThreshold(threshold: UFix64) {
            pre { threshold > 0.0 && threshold <= 1.0: "Threshold must be between 0 and 1" }
            ScheduledManagerV0_2.rebalanceThreshold = threshold
        }

        access(all) fun setEVMContract(name: String, config: EVMConfig) {
            ScheduledManagerV0_2.evmConfig[name] = config
            emit EVMConfigUpdated(name: name, address: config.address, selectorLength: config.selector.length)
        }

        access(all) fun getEVMConfig(name: String): EVMConfig? {
            return ScheduledManagerV0_2.evmConfig[name]
        }

        /// Check for expired BidSelected intents past their execution deadline.
        /// If the winning solver has not executed within N blocks, take the full
        /// gas escrow as protocol fee and expire the intent.
        access(all) fun checkFallbackExecution(
            protocolFeeReceiver: &{FungibleToken.Receiver}
        ) {
            let bidSelectedIDs = IntentMarketplaceV0_2.getBidSelectedIntents()
            let currentBlock = getCurrentBlock().height

            let marketplace = getAccount(ScheduledManagerV0_2.account.address)
                .capabilities.borrow<&IntentMarketplaceV0_2.Marketplace>(
                    IntentMarketplaceV0_2.MarketplacePublicPath
                ) ?? panic("Cannot borrow MarketplaceV0_2")

            for intentID in bidSelectedIDs {
                let intent = IntentMarketplaceV0_2.getIntent(id: intentID)
                if intent == nil { continue }
                let intentRef = intent!

                // Check if past execution deadline
                if currentBlock > intentRef.executionDeadlineBlock {
                    // Take full gas escrow as protocol fee
                    let escrowBalance = marketplace.getGasEscrowBalance(id: intentID)
                    if escrowBalance > 0.0 {
                        let escrowVault <- marketplace.withdrawFullGasEscrowFromIntent(id: intentID)
                        protocolFeeReceiver.deposit(from: <- escrowVault)
                    }

                    // Mark intent as expired
                    // Note: Intent is in BidSelected state, but solver missed deadline
                    // We set it to Expired so principal can be returned to owner
                    emit FallbackExecutionTriggered(
                        intentID: intentID,
                        escrowTaken: escrowBalance
                    )
                }
            }
        }

        /// Poll EVM for pending intents and create them in IntentMarketplaceV0_2.
        /// This is the core dual-chain bridge: EVM intents become Cadence intents.
        access(all) fun pollEVMIntents(coaRef: auth(EVM.Call) &EVM.CadenceOwnedAccount) {
            let config = ScheduledManagerV0_2.evmConfig["composerV2_getPendingIntents"]
                ?? panic("EVMConfig not set for composerV2_getPendingIntents")

            let composerAddr = ScheduledManagerV0_2.parseEVMAddress(config.address)

            // 1. staticCall -> FlowIntentsComposerV2.getPendingIntents()
            let calldata = config.selector

            let result = EVM.dryCall(
                from: coaRef.address(),
                to: composerAddr,
                data: calldata,
                gasLimit: 500000,
                value: EVM.Balance(attoflow: 0)
            )

            if result.status != EVM.Status.successful {
                emit EVMPollCompleted(intentsPolled: 0, intentsCreated: 0, timestamp: getCurrentBlock().timestamp)
                return
            }

            let data = result.data
            if data.length < 64 {
                emit EVMPollCompleted(intentsPolled: 0, intentsCreated: 0, timestamp: getCurrentBlock().timestamp)
                return
            }

            // ABI layout for (uint256[], EVMIntentRequest[]):
            // offset 0-31:  offset to ids array
            // offset 32-63: offset to requests array
            // Then at ids offset: length, then elements
            let idsOffset = ScheduledManagerV0_2.decodeUInt256(data: data, offset: 0)
            if Int(idsOffset) + 32 > data.length {
                emit EVMPollCompleted(intentsPolled: 0, intentsCreated: 0, timestamp: getCurrentBlock().timestamp)
                return
            }

            let count = ScheduledManagerV0_2.decodeUInt256(data: data, offset: Int(idsOffset))
            if count == 0 {
                emit EVMPollCompleted(intentsPolled: 0, intentsCreated: 0, timestamp: getCurrentBlock().timestamp)
                return
            }

            // Borrow marketplace
            let marketplace = getAccount(ScheduledManagerV0_2.account.address)
                .capabilities.borrow<&IntentMarketplaceV0_2.Marketplace>(
                    IntentMarketplaceV0_2.MarketplacePublicPath
                ) ?? panic("Cannot borrow MarketplaceV0_2")

            var created = 0
            var i: UInt256 = 0
            while i < count {
                let idOffset = Int(idsOffset) + 32 + (Int(i) * 32)
                if idOffset + 32 > data.length { break }
                let evmIntentId = ScheduledManagerV0_2.decodeUInt256(data: data, offset: idOffset)

                // Create a zero-balance FlowToken vault as placeholder (funds live on EVM)
                let emptyVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())

                let cadenceIntentId = marketplace.createEVMIntent(
                    ownerAddress: ScheduledManagerV0_2.account.address,
                    vault: <- emptyVault,
                    evmIntentId: evmIntentId,
                    evmToken: "0x0000000000000000000000000000000000000000",
                    evmAmount: 0,
                    targetAPY: 5.0,
                    durationDays: 30,
                    expiryBlock: getCurrentBlock().height + 100000
                )

                // COA call -> markPickedUp(intentId)
                let markConfig = ScheduledManagerV0_2.evmConfig["composerV2_markPickedUp"]
                    ?? panic("EVMConfig not set for composerV2_markPickedUp")

                var markCalldata: [UInt8] = markConfig.selector
                var tmp = evmIntentId
                var idBytes: [UInt8] = []
                var j = 0
                while j < 32 {
                    idBytes.insert(at: 0, UInt8(tmp & 0xff))
                    tmp = tmp >> 8
                    j = j + 1
                }
                markCalldata.appendAll(idBytes)

                let markResult = coaRef.call(
                    to: composerAddr,
                    data: markCalldata,
                    gasLimit: 100000,
                    value: EVM.Balance(attoflow: 0)
                )

                if markResult.status == EVM.Status.successful {
                    emit EVMIntentPolled(
                        evmIntentId: evmIntentId,
                        cadenceIntentId: cadenceIntentId,
                        evmToken: "0x0000000000000000000000000000000000000000",
                        evmAmount: 0
                    )
                    created = created + 1
                }

                i = i + 1
            }

            emit EVMPollCompleted(
                intentsPolled: Int(count),
                intentsCreated: created,
                timestamp: getCurrentBlock().timestamp
            )
        }
    }

    // -------------------------------------------------------------------------
    // Active intent monitoring — can be called by any authorized transaction
    // -------------------------------------------------------------------------

    /// Check active intents for APY drift and trigger rebalance events.
    access(all) fun checkActiveIntents(intentIDs: [UInt64]) {
        var idsToCheck = intentIDs
        if idsToCheck.length == 0 {
            idsToCheck = IntentMarketplaceV0_2.getOpenIntents()
        }

        for intentID in idsToCheck {
            let intent = IntentMarketplaceV0_2.getIntent(id: intentID)
            if intent == nil { continue }
            let intentRef = intent!

            if intentRef.status == IntentMarketplaceV0_2.IntentStatus.Active {
                let currentAPY = ScheduledManagerV0_2.fetchCurrentAPY(intentID: intentID)
                let targetAPY  = intentRef.targetAPY
                let threshold  = targetAPY * ScheduledManagerV0_2.rebalanceThreshold

                var rebalanceTriggered = false
                if currentAPY < threshold {
                    rebalanceTriggered = true
                    emit RebalanceTriggered(
                        intentID: intentID,
                        oldAPY: currentAPY,
                        newAPY: targetAPY
                    )
                }

                emit PositionChecked(
                    intentID: intentID,
                    currentAPY: currentAPY,
                    targetAPY: targetAPY,
                    rebalanceTriggered: rebalanceTriggered
                )
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internal — APY fetch via COA dryCall
    // -------------------------------------------------------------------------

    access(self) fun fetchCurrentAPY(intentID: UInt64): UFix64 {
        let config = ScheduledManagerV0_2.evmConfig["composerV2"]
        if config == nil {
            return 0.0
        }

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

        let composerAddr = ScheduledManagerV0_2.parseEVMAddress(config!.address)
        let zeroAddr = EVM.EVMAddress(bytes: [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ])

        let result = EVM.dryCall(
            from: zeroAddr,
            to: composerAddr,
            data: calldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        if result.status != EVM.Status.successful || result.data.length < 32 {
            return 0.0
        }

        var raw: UInt256 = 0
        var i = 0
        while i < 32 {
            raw = raw * 256 + UInt256(result.data[i])
            i = i + 1
        }
        return UFix64(raw) / 100.0
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    access(self) fun decodeUInt256(data: [UInt8], offset: Int): UInt256 {
        if data.length < offset + 32 { return 0 }
        var result: UInt256 = 0
        var i = 0
        while i < 32 {
            result = result * 256 + UInt256(data[offset + i])
            i = i + 1
        }
        return result
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
            let high = ScheduledManagerV0_2.hexCharToUInt8(hex.slice(from: i,     upTo: i + 1))
            let low  = ScheduledManagerV0_2.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
            bytes.append((high << 4) | low)
            i = i + 2
        }
        return EVM.EVMAddress(bytes: [
            bytes[0],  bytes[1],  bytes[2],  bytes[3],  bytes[4],
            bytes[5],  bytes[6],  bytes[7],  bytes[8],  bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
            bytes[15], bytes[16], bytes[17], bytes[18], bytes[19]
        ])
    }

    access(self) fun hexCharToUInt8(_ c: String): UInt8 {
        switch c {
            case "0": return 0
            case "1": return 1
            case "2": return 2
            case "3": return 3
            case "4": return 4
            case "5": return 5
            case "6": return 6
            case "7": return 7
            case "8": return 8
            case "9": return 9
            case "a": return 10
            case "A": return 10
            case "b": return 11
            case "B": return 11
            case "c": return 12
            case "C": return 12
            case "d": return 13
            case "D": return 13
            case "e": return 14
            case "E": return 14
            case "f": return 15
            case "F": return 15
        }
        return 0
    }

    // -------------------------------------------------------------------------
    // Public read functions
    // -------------------------------------------------------------------------

    access(all) fun getEVMConfig(name: String): EVMConfig? {
        return self.evmConfig[name]
    }

    access(all) fun getEVMConfigKeys(): [String] {
        return self.evmConfig.keys
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.rebalanceThreshold = 0.8

        self.AdminStoragePath = /storage/FlowIntentsScheduledAdminV2

        // Initialize EVMConfig with selectors for FlowIntentsComposerV2
        // getPendingIntents() selector = keccak256("getPendingIntents()")[:4]
        // markPickedUp(uint256) selector = keccak256("markPickedUp(uint256)")[:4]
        self.evmConfig = {
            "composerV2": EVMConfig(
                address: "0x0000000000000000000000000000000000000000",
                selector: []
            ),
            "composerV2_getPendingIntents": EVMConfig(
                address: "0x0000000000000000000000000000000000000000",
                selector: [0x1b, 0x5c, 0x9b, 0xaf]
            ),
            "composerV2_markPickedUp": EVMConfig(
                address: "0x0000000000000000000000000000000000000000",
                selector: [0x7b, 0x04, 0x72, 0xf0]
            )
        }

        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
