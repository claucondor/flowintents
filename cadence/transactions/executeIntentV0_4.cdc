/// executeIntentV0_4.cdc
/// USER executes a BidSelected intent via IntentExecutorV0_4.executeIntent().
/// Key difference from V0_3: the USER signs this transaction, not the solver.
/// The user's COA is used for the cross-VM call.
/// Commission escrow is paid to the winning solver.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentExecutorV0_4 from "IntentExecutorV0_4"
import BidManagerV0_4 from "BidManagerV0_4"

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let userAddress: Address
    let userFlowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let solverFlowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.userAddress = signer.address

        // User's COA for cross-VM EVM calls
        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("User must have a COA at /storage/evm")

        // User's FlowToken vault — principal will be withdrawn from here
        self.userFlowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow user FlowToken vault")

        // Solver's FlowToken receiver for commission payment
        // We look up the winning solver's address and get their receiver
        let winningBid = BidManagerV0_4.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")
        let solverAddress = winningBid.solverAddress

        // Get solver's FlowToken receiver via public capability
        self.solverFlowReceiver = getAccount(solverAddress)
            .capabilities.borrow<&{FungibleToken.Receiver}>(
                /public/flowTokenReceiver
            ) ?? panic("Cannot borrow solver FlowToken receiver")
    }

    execute {
        IntentExecutorV0_4.executeIntent(
            intentID: intentID,
            userAddress: self.userAddress,
            coa: self.coa,
            userFlowVault: self.userFlowVault,
            solverFlowReceiver: self.solverFlowReceiver
        )
        log("V0_4 Intent ".concat(intentID.toString()).concat(" executed by user — commission paid to solver"))
    }
}
