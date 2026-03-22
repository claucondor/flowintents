/// createIntent.cdc
/// Creates a new yield intent in the FlowIntents marketplace.
/// The signer's FungibleToken vault funds are moved into the intent resource.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_1 from "IntentMarketplaceV0_1"

transaction(
    amount: UFix64,
    targetAPY: UFix64,
    durationDays: UInt64,
    expiryBlock: UInt64
) {
    let marketplace: &IntentMarketplaceV0_1.Marketplace
    let vault: @{FungibleToken.Vault}
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        // Borrow the marketplace via public capability
        self.marketplace = getAccount(IntentMarketplaceV0_1.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_1.Marketplace>(
                IntentMarketplaceV0_1.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_1")

        // Withdraw principal from signer's FlowToken vault
        let flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow FlowToken vault")

        self.vault <- flowVault.withdraw(amount: amount)
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createIntent(
            ownerAddress: self.signerAddress,
            vault: <- self.vault,
            targetAPY: targetAPY,
            durationDays: durationDays,
            expiryBlock: expiryBlock
        )
        log("Intent created with ID: ".concat(intentID.toString()))
    }
}
