/// executeIntent.cdc
/// Winning solver executes a BidSelected intent via Cross-VM COA call.
/// The solver's COA sends the encodedBatch to FlowIntentsComposer.sol.

import EVM from "EVM"
import IntentExecutorV0_1 from "IntentExecutorV0_1"

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let solverAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.solverAddress = signer.address

        // Borrow solver's COA with Call entitlement
        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("Solver must have a Cadence Owned Account at /storage/evm")
    }

    execute {
        IntentExecutorV0_1.executeIntent(
            intentID: intentID,
            solverAddress: self.solverAddress,
            coa: self.coa
        )
        log("Intent ".concat(intentID.toString()).concat(" executed via COA"))
    }
}
