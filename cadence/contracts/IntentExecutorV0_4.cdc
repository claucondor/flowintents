/// IntentExecutorV0_4.cdc
/// V0_4 Executor — USER signs and executes the strategy transaction.
///
/// Key differences from V0_3:
///   - The USER's COA is used, not the solver's
///   - User withdraws principal from their own wallet at execution time
///   - Delivery routing based on DeliverySide enum:
///     * CadenceVault: bridge tokens back from EVM to Cadence vault (TODO: bridge API)
///     * COA: tokens stay in user's COA on EVM
///     * ExternalEVM: ComposerV4 sweeps to external EVM address
///     * ExternalCadence: bridge + send to another Cadence address (TODO: bridge API)
///   - Commission escrow is paid to solver after successful execution
///
/// IMPORTANT: This is a NEW contract — does NOT modify V0_3.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"
import BidManagerV0_4 from "BidManagerV0_4"

access(all) contract IntentExecutorV0_4 {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event IntentExecuted(
        intentID: UInt64,
        executorAddress: Address,
        solverAddress: Address,
        solverEVMAddress: String,
        composerAddress: String,
        gasUsed: UInt64,
        deliverySide: UInt8
    )

    access(all) event IntentExecutionFailed(
        intentID: UInt64,
        reason: String
    )

    access(all) event CommissionPaymentToSolver(
        intentID: UInt64,
        solverAddress: Address,
        amount: UFix64
    )

    // -------------------------------------------------------------------------
    // EVM Config
    // -------------------------------------------------------------------------

    access(all) struct EVMConfig {
        access(all) let address: String
        access(all) let selector: [UInt8]
        init(address: String, selector: [UInt8]) {
            self.address = address
            self.selector = selector
        }
    }

    access(self) var evmConfig: {String: EVMConfig}
    access(all) var composerAddress: String
    access(all) let AdminStoragePath: StoragePath

    access(all) event EVMConfigUpdated(name: String, address: String, selectorLength: Int)

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setComposerAddress(addr: String) {
            IntentExecutorV0_4.composerAddress = addr
            let composerKeys = ["composer", "composer_executeStrategyWithFunds"]
            for key in composerKeys {
                if let existing = IntentExecutorV0_4.evmConfig[key] {
                    IntentExecutorV0_4.evmConfig[key] = EVMConfig(
                        address: addr,
                        selector: existing.selector
                    )
                }
            }
        }

        access(all) fun setEVMContract(name: String, config: EVMConfig) {
            IntentExecutorV0_4.evmConfig[name] = config
            if name == "composer" || name == "composer_executeStrategyWithFunds" {
                IntentExecutorV0_4.composerAddress = config.address
            }
            emit EVMConfigUpdated(name: name, address: config.address, selectorLength: config.selector.length)
        }

        access(all) fun getEVMConfig(name: String): EVMConfig? {
            return IntentExecutorV0_4.evmConfig[name]
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

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

    access(self) fun parseEVMAddress(_ hexAddr: String): EVM.EVMAddress {
        var hex = hexAddr
        if hex.length >= 2 && hex.slice(from: 0, upTo: 2) == "0x" {
            hex = hex.slice(from: 2, upTo: hex.length)
        }
        while hex.length < 40 {
            hex = "0".concat(hex)
        }
        var bytes: [UInt8] = []
        var i = 0
        while i < 40 {
            let high = IntentExecutorV0_4.hexCharToUInt8(hex.slice(from: i,     upTo: i + 1))
            let low  = IntentExecutorV0_4.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
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

    /// Encode calldata for executeStrategyWithFunds(bytes encodedBatch, address recipient).
    /// Selector: 0x7661a94a  (keccak256("executeStrategyWithFunds(bytes,address)")[0:4])
    access(self) fun encodeExecuteStrategyWithFunds(encodedBatch: [UInt8], recipient: EVM.EVMAddress): [UInt8] {
        var calldata: [UInt8] = [0x76, 0x61, 0xa9, 0x4a]

        // ABI head slot 1: offset of bytes param = 0x40 (64)
        var offsetBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            offsetBytes.insert(at: 0, 0)
            j = j + 1
        }
        offsetBytes[31] = 0x40
        calldata.appendAll(offsetBytes)

        // ABI head slot 2: recipient address left-padded to 32 bytes
        j = 0
        while j < 12 {
            calldata.append(0)
            j = j + 1
        }
        let addrBytes = recipient.bytes
        calldata.append(addrBytes[0]);  calldata.append(addrBytes[1])
        calldata.append(addrBytes[2]);  calldata.append(addrBytes[3])
        calldata.append(addrBytes[4]);  calldata.append(addrBytes[5])
        calldata.append(addrBytes[6]);  calldata.append(addrBytes[7])
        calldata.append(addrBytes[8]);  calldata.append(addrBytes[9])
        calldata.append(addrBytes[10]); calldata.append(addrBytes[11])
        calldata.append(addrBytes[12]); calldata.append(addrBytes[13])
        calldata.append(addrBytes[14]); calldata.append(addrBytes[15])
        calldata.append(addrBytes[16]); calldata.append(addrBytes[17])
        calldata.append(addrBytes[18]); calldata.append(addrBytes[19])

        // ABI: length of bytes param
        let batchLen = encodedBatch.length
        var lenBytes: [UInt8] = []
        var tmp: Int = batchLen
        j = 0
        while j < 32 {
            lenBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(lenBytes)

        // The bytes data
        calldata.appendAll(encodedBatch)

        // Pad to 32-byte boundary
        let remainder = batchLen % 32
        if remainder != 0 {
            let padCount = 32 - remainder
            j = 0
            while j < padCount {
                calldata.append(0)
                j = j + 1
            }
        }

        return calldata
    }

    // -------------------------------------------------------------------------
    // Execute intent — called by the USER (not the solver)
    // -------------------------------------------------------------------------

    /// Execute a winning intent. Called by the intent OWNER (user).
    /// The user provides:
    ///   - Their COA for cross-VM EVM calls
    ///   - Their FlowToken vault to withdraw principal from
    ///   - A solver FlowToken receiver for commission payment
    ///
    /// Flow:
    ///   1. Withdraw principal from user's FlowToken vault
    ///   2. Deposit into user's COA via coa.deposit()
    ///   3. Call ComposerV4.executeStrategyWithFunds(encodedBatch, recipient)
    ///      - recipient depends on deliverySide
    ///   4. If CadenceVault delivery: TODO bridge back via Flow cross-VM bridge
    ///   5. Pay commission escrow to solver
    ///   6. Update intent status
    access(all) fun executeIntent(
        intentID: UInt64,
        userAddress: Address,
        coa: auth(EVM.Call) &EVM.CadenceOwnedAccount,
        userFlowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault,
        solverFlowReceiver: &{FungibleToken.Receiver}
    ) {
        pre {
            IntentExecutorV0_4.composerAddress != "0x0000000000000000000000000000000000000000":
                "IntentExecutorV0_4: composerAddress not set — call Admin.setComposerAddress() first"
        }

        // ------------------------------------------------------------------
        // Verify state
        // ------------------------------------------------------------------
        let intent = IntentMarketplaceV0_4.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.intentOwner == userAddress,
            message: "Only the intent owner can execute this intent"
        )
        assert(
            intent.status == IntentMarketplaceV0_4.IntentStatus.BidSelected,
            message: "Intent must be in BidSelected status for execution"
        )

        let winningBid = BidManagerV0_4.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")

        // ------------------------------------------------------------------
        // Get encodedBatch from winning bid
        // ------------------------------------------------------------------
        let encodedBatch = winningBid.encodedBatch.slice(from: 0, upTo: winningBid.encodedBatch.length)
        assert(encodedBatch.length > 0, message: "Encoded batch is empty")

        let composerEVMAddress = IntentExecutorV0_4.parseEVMAddress(IntentExecutorV0_4.composerAddress)

        // Borrow marketplace
        let marketplace = getAccount(self.account.address)
            .capabilities.borrow<&IntentMarketplaceV0_4.Marketplace>(
                IntentMarketplaceV0_4.MarketplacePublicPath
            ) ?? panic("Cannot borrow MarketplaceV0_4")

        // ------------------------------------------------------------------
        // Step 1: Withdraw principal from user's FlowToken vault
        // ------------------------------------------------------------------
        let principalVault <- userFlowVault.withdraw(amount: intent.principalAmount)
        let principalBalance = principalVault.balance

        // ------------------------------------------------------------------
        // Step 2: Convert UFix64 -> attoFLOW and deposit into COA
        // ------------------------------------------------------------------
        let attoflow: UInt = UInt(principalBalance * 100_000_000.0) * 10_000_000_000
        let flowVault <- principalVault as! @FlowToken.Vault
        coa.deposit(from: <- flowVault)

        // ------------------------------------------------------------------
        // Step 3: Determine recipient based on deliverySide
        // ------------------------------------------------------------------
        var recipientAddr: EVM.EVMAddress = coa.address()  // default: user's COA

        if intent.deliverySide == IntentMarketplaceV0_4.DeliverySide.ExternalEVM {
            // Deliver to external EVM address
            if let extAddr = intent.deliveryAddress {
                recipientAddr = IntentExecutorV0_4.parseEVMAddress(extAddr)
            }
        }
        // For COA delivery: recipient = coa.address() (already set as default)
        // For CadenceVault / ExternalCadence: recipient = coa.address(),
        //   then bridge back in a post-step (TODO)

        // ------------------------------------------------------------------
        // Step 4: Call ComposerV4.executeStrategyWithFunds
        // ------------------------------------------------------------------
        let calldata = IntentExecutorV0_4.encodeExecuteStrategyWithFunds(
            encodedBatch: encodedBatch,
            recipient: recipientAddr
        )

        let result = coa.call(
            to: composerEVMAddress,
            data: calldata,
            gasLimit: 500000,
            value: EVM.Balance(attoflow: attoflow)
        )

        assert(
            result.status == EVM.Status.successful,
            message: "FlowIntentsComposerV4 call failed — EVM reverted"
        )

        // ------------------------------------------------------------------
        // Step 5: Handle CadenceVault delivery (bridge back)
        // ------------------------------------------------------------------
        if intent.deliverySide == IntentMarketplaceV0_4.DeliverySide.CadenceVault {
            // TODO: Bridge tokens back from EVM to Cadence FungibleToken vault
            // via Flow cross-VM bridge. The exact bridge API may vary.
            // For now, tokens remain in the user's COA — the user can manually
            // bridge them back using the Flow EVM bridge contract.
            // Once the bridge API is standardized, this will be automated.
        }

        if intent.deliverySide == IntentMarketplaceV0_4.DeliverySide.ExternalCadence {
            // TODO: Bridge tokens back from EVM, then send to the target
            // Cadence address specified in intent.deliveryAddress.
            // Same bridge API dependency as CadenceVault delivery.
        }

        // ------------------------------------------------------------------
        // Step 6: Update intent status to Active
        // ------------------------------------------------------------------
        marketplace.setActiveOnIntent(id: intentID)
        marketplace.setExecutedByOnIntent(id: intentID, executorAddress: userAddress)

        // ------------------------------------------------------------------
        // Step 7: Pay commission escrow to solver
        // ------------------------------------------------------------------
        let commissionVault <- marketplace.withdrawFullCommissionEscrowFromIntent(id: intentID)
        let commissionAmount = commissionVault.balance
        if commissionAmount > 0.0 {
            solverFlowReceiver.deposit(from: <- commissionVault)

            emit CommissionPaymentToSolver(
                intentID: intentID,
                solverAddress: winningBid.solverAddress,
                amount: commissionAmount
            )
        } else {
            destroy commissionVault
        }

        // ------------------------------------------------------------------
        // Step 8: Record execution
        // ------------------------------------------------------------------
        marketplace.recordExecutionOnIntent(
            id: intentID,
            txHash: "user-exec-v4",
            executedAt: getCurrentBlock().timestamp
        )

        emit IntentExecuted(
            intentID: intentID,
            executorAddress: userAddress,
            solverAddress: winningBid.solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            composerAddress: IntentExecutorV0_4.composerAddress,
            gasUsed: result.gasUsed,
            deliverySide: intent.deliverySide.rawValue
        )
    }

    // -------------------------------------------------------------------------
    // Public read helpers
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
        self.composerAddress = "0x0000000000000000000000000000000000000000"

        self.evmConfig = {
            "composer": EVMConfig(
                address: "0x0000000000000000000000000000000000000000",
                selector: []
            ),
            "composer_executeStrategyWithFunds": EVMConfig(
                address: "0x0000000000000000000000000000000000000000",
                selector: [0x76, 0x61, 0xa9, 0x4a]
            )
        }

        self.AdminStoragePath = /storage/FlowIntentsExecutorAdminV4
        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
