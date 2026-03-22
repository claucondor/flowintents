/// executeIntentV0_2.cdc
/// Winning solver executes a BidSelected intent via IntentExecutorV0_2.executeIntentV2().
/// Handles gas escrow payment to solver + refund to owner.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentExecutorV0_2 from "IntentExecutorV0_2"
import IntentMarketplaceV0_2 from "IntentMarketplaceV0_2"

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let solverAddress: Address
    let solverReceiver: &{FungibleToken.Receiver}
    let ownerReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.solverAddress = signer.address

        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("Solver must have a COA at /storage/evm")

        // Solver's FlowToken receiver for gas payment
        self.solverReceiver = signer.storage
            .borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Cannot borrow solver FlowToken vault")

        // Owner's FlowToken receiver for gas escrow refund
        // In this test, solver == owner (same emulator account)
        let intent = IntentMarketplaceV0_2.getIntent(id: intentID)
            ?? panic("Intent not found")
        let ownerAccount = getAccount(intent.intentOwner)
        self.ownerReceiver = ownerAccount
            .capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            ?? panic("Cannot borrow owner FlowToken receiver")
    }

    execute {
        IntentExecutorV0_2.executeIntentV2(
            intentID: intentID,
            solverAddress: self.solverAddress,
            coa: self.coa,
            solverFlowReceiver: self.solverReceiver,
            ownerFlowReceiver: self.ownerReceiver
        )
        log("V0_2 Intent ".concat(intentID.toString()).concat(" executed with gas escrow accounting"))
    }
}
