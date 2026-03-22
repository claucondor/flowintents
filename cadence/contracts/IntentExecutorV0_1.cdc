/// IntentExecutorV0_1.cdc
/// Executes a winning intent's strategy via Cross-VM COA call to FlowIntentsComposer.sol.
/// A single coa.call() sends the encodedBatch; EVM revert propagates as Cadence tx revert.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import IntentMarketplaceV0_1 from "IntentMarketplaceV0_1"
import BidManagerV0_1 from "BidManagerV0_1"

access(all) contract IntentExecutorV0_1 {

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

    /// FlowIntentsComposer.sol address on Flow EVM — set by admin after deploy
    access(all) var composerAddress: String

    access(all) let AdminStoragePath: StoragePath

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setComposerAddress(addr: String) {
            IntentExecutorV0_1.composerAddress = addr
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
            let high = IntentExecutorV0_1.hexCharToUInt8(hex.slice(from: i,     upTo: i + 1))
            let low  = IntentExecutorV0_1.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
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
            to: IntentExecutorV0_1.parseEVMAddress(IntentExecutorV0_1.composerAddress),
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
        // Guard: composer must be configured before any execution
        pre {
            IntentExecutorV0_1.composerAddress != "0x0000000000000000000000000000000000000000":
                "IntentExecutorV0_1: composerAddress not set — call Admin.setComposerAddress() first"
        }

        // ------------------------------------------------------------------
        // Verify state
        // ------------------------------------------------------------------
        let intent = IntentMarketplaceV0_1.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplaceV0_1.IntentStatus.BidSelected,
            message: "Intent must be in BidSelected status for execution"
        )

        let winningBid = BidManagerV0_1.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")
        assert(
            winningBid.solverAddress == solverAddress,
            message: "Only the winning solver can execute this intent"
        )

        // ------------------------------------------------------------------
        // Get encodedBatch from winning bid
        // ------------------------------------------------------------------
        // .slice() copies the [UInt8] array from the &Bid reference
        let encodedBatch = winningBid.encodedBatch.slice(from: 0, upTo: winningBid.encodedBatch.length)
        assert(encodedBatch.length > 0, message: "Encoded batch is empty")

        let composerEVMAddress = IntentExecutorV0_1.parseEVMAddress(IntentExecutorV0_1.composerAddress)

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
        let marketplace = getAccount(self.account.address)
            .capabilities.borrow<&IntentMarketplaceV0_1.Marketplace>(
                IntentMarketplaceV0_1.MarketplacePublicPath
            ) ?? panic("Cannot borrow Marketplace")
        marketplace.setActiveOnIntent(id: intentID)

        emit IntentExecuted(
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            composerAddress: IntentExecutorV0_1.composerAddress,
            gasUsed: result.gasUsed
        )
    }

    /// Complete an intent by executing a withdrawal batch and returning funds to owner.
    /// The withdrawalBatch is an ABI-encoded BatchStep[] that reverses the deposit strategy
    /// (e.g. redeem from MORE Finance, unwrap WFLOW, etc.).
    ///
    /// NOTE: After the EVM batch runs, the funds are in the COA's EVM balance.
    /// Bridging from EVM back to Cadence via the Flow cross-VM bridge is the solver's
    /// responsibility and must happen in the same transaction via the bridge contract.
    /// Until the cross-VM bridge wrappers are standardized, this function panics to
    /// prevent silent fund loss.
    access(all) fun completeIntent(
        intentID: UInt64,
        solverAddress: Address,
        coa: auth(EVM.Call) &EVM.CadenceOwnedAccount,
        ownerReceiver: &{FungibleToken.Receiver}
    ) {
        pre {
            IntentExecutorV0_1.composerAddress != "0x0000000000000000000000000000000000000000":
                "IntentExecutorV0_1: composerAddress not set"
        }

        let intent = IntentMarketplaceV0_1.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplaceV0_1.IntentStatus.Active,
            message: "Intent must be Active to complete"
        )

        let winningBid = BidManagerV0_1.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found")
        assert(winningBid.solverAddress == solverAddress, message: "Only winning solver can complete")

        // TODO Sprint 4: Implement withdrawal batch execution + cross-VM bridge return.
        // The withdrawal encodedBatch is protocol/strategy-specific and must be provided
        // by the solver. After EVM execution, funds must be bridged back via:
        //   EVM.withdrawTokens() or the Flow EVM bridge contract.
        // Until this is standardized, panic to prevent accidental fund loss.
        panic("completeIntent: cross-VM bridge return not yet implemented — requires Sprint 4 bridge wrappers")
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        // Placeholder — update via Admin after EVM contracts are deployed
        self.composerAddress = "0x0000000000000000000000000000000000000000"

        self.AdminStoragePath = /storage/FlowIntentsExecutorAdmin
        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
