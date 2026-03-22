/// executeIntentV0_3.cdc
/// Winning solver executes a BidSelected intent via IntentExecutorV0_3.executeIntentV2().
/// Solver receives the FULL gas escrow — no refund to user.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentExecutorV0_3 from "IntentExecutorV0_3"

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let solverAddress: Address
    let solverReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.solverAddress = signer.address

        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("Solver must have a COA at /storage/evm")

        // Solver's FlowToken receiver for full gas escrow payment
        self.solverReceiver = signer.storage
            .borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Cannot borrow solver FlowToken vault")
    }

    execute {
        IntentExecutorV0_3.executeIntentV2(
            intentID: intentID,
            solverAddress: self.solverAddress,
            coa: self.coa,
            solverFlowReceiver: self.solverReceiver
        )
        log("V0_3 Intent ".concat(intentID.toString()).concat(" executed — solver received full gas escrow"))
    }
}
