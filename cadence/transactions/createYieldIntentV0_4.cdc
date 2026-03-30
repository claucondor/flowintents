/// createYieldIntentV0_4.cdc
/// Creates a new YIELD intent in IntentMarketplaceV0_4.
/// User declares principal amount but does NOT deposit it — only commission escrow is deposited.
/// User specifies deliverySide and optional deliveryAddress.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"

transaction(
    principalAmount: UFix64,
    targetAPY: UFix64,
    deliverySide: UInt8,
    deliveryAddress: String?,
    durationDays: UInt64,
    expiryBlock: UInt64,
    commissionEscrowAmount: UFix64
) {
    let marketplace: &IntentMarketplaceV0_4.Marketplace
    let commissionEscrowVault: @FlowToken.Vault
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = getAccount(IntentMarketplaceV0_4.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_4.Marketplace>(
                IntentMarketplaceV0_4.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_4")

        let flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow FlowToken vault")

        // Only withdraw commission escrow — principal stays in wallet
        self.commissionEscrowVault <- flowVault.withdraw(amount: commissionEscrowAmount) as! @FlowToken.Vault
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createYieldIntent(
            ownerAddress: self.signerAddress,
            principalAmount: principalAmount,
            targetAPY: targetAPY,
            deliverySide: deliverySide,
            deliveryAddress: deliveryAddress,
            durationDays: durationDays,
            expiryBlock: expiryBlock,
            commissionEscrowVault: <- self.commissionEscrowVault
        )
        log("V0_4 YIELD Intent created with ID: ".concat(intentID.toString()))
    }
}
