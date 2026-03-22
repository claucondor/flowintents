/// cancelIntent.cdc
/// Cancels an open intent and returns the principal to the signer.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_1 from "IntentMarketplaceV0_1"

transaction(intentID: UInt64) {
    let marketplace: &IntentMarketplaceV0_1.Marketplace
    let receiver: &{FungibleToken.Receiver}
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = IntentMarketplaceV0_1.account.storage
            .borrow<&IntentMarketplaceV0_1.Marketplace>(
                from: IntentMarketplaceV0_1.MarketplaceStoragePath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_1")

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
