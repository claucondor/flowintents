/// createSwapIntentV0_3.cdc
/// Creates a new SWAP intent in IntentMarketplaceV0_3.
/// Solver must deliver at least `minAmountOut` of the target token.
/// Gas escrow is paid in full to the winning solver on execution.

import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"

transaction(
    amount: UFix64,
    minAmountOut: UFix64,
    maxFeeBPS: UInt64,
    durationDays: UInt64,
    expiryBlock: UInt64,
    gasEscrowAmount: UFix64
) {
    let marketplace: &IntentMarketplaceV0_3.Marketplace
    let vault: @{FungibleToken.Vault}
    let gasEscrowVault: @FlowToken.Vault
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
                IntentMarketplaceV0_3.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_3")

        let flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow FlowToken vault")

        // Withdraw principal (the FLOW to be swapped)
        self.vault <- flowVault.withdraw(amount: amount)
        // Withdraw gas escrow separately
        self.gasEscrowVault <- flowVault.withdraw(amount: gasEscrowAmount) as! @FlowToken.Vault
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createSwapIntent(
            ownerAddress: self.signerAddress,
            vault: <- self.vault,
            minAmountOut: minAmountOut,
            maxFeeBPS: maxFeeBPS,
            durationDays: durationDays,
            expiryBlock: expiryBlock,
            gasEscrowVault: <- self.gasEscrowVault
        )
        log("V0_3 SWAP Intent created with ID: ".concat(intentID.toString()))
    }
}
