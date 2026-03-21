/// cancelIntent.cdc
/// Cancels an open intent and returns the principal to the signer.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplace from "IntentMarketplace"

transaction(intentID: UInt64) {
    let marketplace: &IntentMarketplace.Marketplace
    let receiver: &{FungibleToken.Receiver}
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = IntentMarketplace.account.storage
            .borrow<&IntentMarketplace.Marketplace>(
                from: IntentMarketplace.MarketplaceStoragePath
            ) ?? panic("Cannot borrow IntentMarketplace")

        self.receiver = signer.storage
            .borrow<&{FungibleToken.Receiver}>(from: /storage/flowTokenVault)
            ?? panic("Cannot borrow FlowToken receiver")

        self.signerAddress = signer.address
    }

    execute {
        self.marketplace.cancelIntent(
            id: intentID,
            ownerAddress: self.signerAddress,
            receiver: self.receiver
        )
        log("Intent ".concat(intentID.toString()).concat(" cancelled"))
    }
}
