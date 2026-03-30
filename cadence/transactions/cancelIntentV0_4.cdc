/// cancelIntentV0_4.cdc
/// Cancels an open V0_4 intent and returns the commission escrow to the owner.
/// No principal to return since it was never deposited.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"

transaction(intentID: UInt64) {
    let marketplace: &IntentMarketplaceV0_4.Marketplace
    let receiver: &{FungibleToken.Receiver}
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = getAccount(IntentMarketplaceV0_4.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_4.Marketplace>(
                IntentMarketplaceV0_4.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_4")

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
        log("V0_4 Intent ".concat(intentID.toString()).concat(" cancelled — commission escrow refunded"))
    }
}
