/// createIntentV0_2.cdc
/// Creates a new yield intent in the IntentMarketplaceV0_2 (dual-chain marketplace)
/// with gas escrow for solver execution payment.
/// The signer's FlowToken vault funds are split into principal + gas escrow.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_2 from "IntentMarketplaceV0_2"

transaction(
    amount: UFix64,
    targetAPY: UFix64,
    durationDays: UInt64,
    expiryBlock: UInt64,
    gasEscrowAmount: UFix64
) {
    let marketplace: &IntentMarketplaceV0_2.Marketplace
    let vault: @{FungibleToken.Vault}
    let gasEscrowVault: @FlowToken.Vault
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = getAccount(IntentMarketplaceV0_2.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_2.Marketplace>(
                IntentMarketplaceV0_2.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_2")

        let flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow FlowToken vault")

        // Withdraw principal
        self.vault <- flowVault.withdraw(amount: amount)
        // Withdraw gas escrow
        self.gasEscrowVault <- flowVault.withdraw(amount: gasEscrowAmount) as! @FlowToken.Vault
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createIntent(
            ownerAddress: self.signerAddress,
            vault: <- self.vault,
            targetAPY: targetAPY,
            durationDays: durationDays,
            expiryBlock: expiryBlock,
            gasEscrowVault: <- self.gasEscrowVault
        )
        log("V0_2 Intent created with ID: ".concat(intentID.toString()).concat(" (with gas escrow)"))
    }
}
