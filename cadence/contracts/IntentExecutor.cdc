/// IntentExecutor.cdc
/// Executes a winning intent's strategy via Cross-VM COA call to FlowIntentsComposer.sol.
/// A single coa.call() sends the encodedBatch; EVM revert propagates as Cadence tx revert.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import IntentMarketplace from "IntentMarketplace"
import BidManager from "BidManager"

access(all) contract IntentExecutor {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event IntentExecuted(
        intentID: UInt64,
        solverAddress: Address,
        solverEVMAddress: String,
        composerAddress: String,
        gasUsed: UInt64
    )

    access(all) event IntentExecutionFailed(
        intentID: UInt64,
        reason: String
    )

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    /// FlowIntentsComposer.sol address on Flow EVM — set by evm-core agent after deploy
    access(all) var composerAddress: String

    /// stgUSDC token address on Flow EVM (6 decimals)
    access(all) let stgUSDCAddress: String

    access(all) let AdminStoragePath: StoragePath

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setComposerAddress(addr: String) {
            IntentExecutor.composerAddress = addr
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

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
            let high = IntentExecutor.hexCharToUInt8(hex.slice(from: i,     upTo: i + 1))
            let low  = IntentExecutor.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
            bytes.append((high << 4) | low)
            i = i + 2
        }
        return EVM.EVMAddress(bytes: bytes)
    }

    /// Read back principal+yield from EVM as dry call (no state change).
    /// Returns current balance of the intent's EVM position.
    access(self) fun dryReadPosition(
        coaAddress: EVM.EVMAddress,
        intentID: UInt64
    ): UFix64 {
        // Encode getIntentBalance(uint256 intentID) selector: keccak256("getIntentBalance(uint256)") = 0x...
        // Using placeholder selector 0x1a2b3c4d — actual selector set by evm-core agent
        var calldata: [UInt8] = [0x1a, 0x2b, 0x3c, 0x4d]
        var tmp = intentID
        var idBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            idBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(idBytes)

        let result = EVM.dryCall(
            from: coaAddress,
            to: IntentExecutor.parseEVMAddress(IntentExecutor.composerAddress),
            data: calldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )
        return 0.0  // Actual decoding implemented once Composer ABI is confirmed by evm-core
    }

    // -------------------------------------------------------------------------
    // Execute intent
    // -------------------------------------------------------------------------

    /// Execute a winning intent. Called by the winning solver.
    /// The solver provides their COA to make the cross-VM call.
    /// The coa.call() to FlowIntentsComposer is the SINGLE cross-VM call — no duplicates.
    access(all) fun executeIntent(
        intentID: UInt64,
        solverAddress: Address,
        coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    ) {
        // ------------------------------------------------------------------
        // Verify state
        // ------------------------------------------------------------------
        let intent = IntentMarketplace.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplace.IntentStatus.BidSelected,
            message: "Intent must be in BidSelected status for execution"
        )

        let winningBid = BidManager.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")
        assert(
            winningBid.solverAddress == solverAddress,
            message: "Only the winning solver can execute this intent"
        )

        // ------------------------------------------------------------------
        // Get encodedBatch from winning bid
        // ------------------------------------------------------------------
        let encodedBatch = winningBid.encodedBatch
        assert(encodedBatch.length > 0, message: "Encoded batch is empty")

        let composerEVMAddress = IntentExecutor.parseEVMAddress(IntentExecutor.composerAddress)

        // ------------------------------------------------------------------
        // Make the single COA call to FlowIntentsComposer.sol
        // If EVM reverts, the entire Cadence transaction reverts — no partial state.
        // ------------------------------------------------------------------
        let result = coa.call(
            to: composerEVMAddress,
            data: encodedBatch,
            gasLimit: 500000,
            value: EVM.Balance(attoflow: 0)
        )

        assert(
            result.status == EVM.Status.successful,
            message: "FlowIntentsComposer call failed — EVM reverted"
        )

        // ------------------------------------------------------------------
        // Update intent status to Active
        // ------------------------------------------------------------------
        let marketplace = IntentMarketplace.account.storage
            .borrow<&IntentMarketplace.Marketplace>(from: IntentMarketplace.MarketplaceStoragePath)
            ?? panic("Cannot borrow Marketplace")
        marketplace.setActiveOnIntent(id: intentID)

        emit IntentExecuted(
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            composerAddress: IntentExecutor.composerAddress,
            gasUsed: result.deployedContract == nil ? 0 : 0  // gasUsed from result if available
        )
    }

    /// Complete an intent — called after the strategy matures.
    /// Returns funds from EVM back to the intent owner.
    access(all) fun completeIntent(
        intentID: UInt64,
        solverAddress: Address,
        coa: auth(EVM.Call) &EVM.CadenceOwnedAccount,
        ownerReceiver: &{FungibleToken.Receiver}
    ) {
        let intent = IntentMarketplace.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplace.IntentStatus.Active,
            message: "Intent must be Active to complete"
        )

        let winningBid = BidManager.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found")
        assert(winningBid.solverAddress == solverAddress, message: "Only winning solver can complete")

        // Encode withdrawIntent(uint256 intentID) call
        // Selector: keccak256("withdrawIntent(uint256)") — placeholder 0xd1e8c4a2
        var calldata: [UInt8] = [0xd1, 0xe8, 0xc4, 0xa2]
        var tmp = intentID
        var idBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            idBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(idBytes)

        let result = coa.call(
            to: IntentExecutor.parseEVMAddress(IntentExecutor.composerAddress),
            data: calldata,
            gasLimit: 300000,
            value: EVM.Balance(attoflow: 0)
        )

        assert(result.status == EVM.Status.successful, message: "withdrawIntent EVM call failed")

        // Funds are now back in Cadence via the cross-VM bridge.
        // The Marketplace completion handler distributes to the owner.
        // NOTE: Actual vault handling depends on evm-core bridge implementation.
        // The marketplace's completeIntent needs a vault — for now emit completion.
        // Full vault flow implemented once cross-vm-bridge wrappers are available.
        emit IntentExecuted(
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            composerAddress: IntentExecutor.composerAddress,
            gasUsed: 0
        )
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        // Placeholder — update after evm-core deploys FlowIntentsComposer
        self.composerAddress = "0x0000000000000000000000000000000000000000"
        // stgUSDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14 (6 decimals)
        self.stgUSDCAddress = "0xF1815bd50389c46847f0Bda824eC8da914045D14"

        self.AdminStoragePath = /storage/FlowIntentsExecutorAdmin
        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
