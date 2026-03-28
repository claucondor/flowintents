export const CREATE_SWAP_INTENT_TX = `
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

        self.vault <- flowVault.withdraw(amount: amount)
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
`;

export const CREATE_YIELD_INTENT_TX = `
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"

transaction(
    amount: UFix64,
    targetAPY: UFix64,
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

        self.vault <- flowVault.withdraw(amount: amount)
        self.gasEscrowVault <- flowVault.withdraw(amount: gasEscrowAmount) as! @FlowToken.Vault
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createYieldIntent(
            ownerAddress: self.signerAddress,
            vault: <- self.vault,
            targetAPY: targetAPY,
            durationDays: durationDays,
            expiryBlock: expiryBlock,
            gasEscrowVault: <- self.gasEscrowVault
        )
        log("V0_3 Intent created with ID: ".concat(intentID.toString()).concat(" (with gas escrow)"))
    }
}
`;

export const SUBMIT_BID_TX = `
import BidManagerV0_3 from "BidManagerV0_3"

transaction(
    intentID: UInt64,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?,
    targetChain: String?,
    maxGasBid: UFix64,
    strategy: String,
    encodedBatch: [UInt8]
) {
    let solverAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.solverAddress = signer.address
    }

    execute {
        let bidID = BidManagerV0_3.submitBid(
            intentID: intentID,
            solverAddress: self.solverAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            estimatedFeeBPS: estimatedFeeBPS,
            targetChain: targetChain,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch
        )
        log("V0_3 Bid ".concat(bidID.toString()).concat(" submitted for intent ").concat(intentID.toString()))
    }
}
`;

export const SELECT_WINNER_TX = `
import BidManagerV0_3 from "BidManagerV0_3"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_3.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("V0_3 Winner selected for intent ".concat(intentID.toString()))
    }
}
`;

export const EXECUTE_INTENT_TX = `
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
        log("V0_3 Intent ".concat(intentID.toString()).concat(" executed"))
    }
}
`;

export const GET_OPEN_INTENTS_SCRIPT = `
import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"

access(all) fun main(): [UInt64] {
    let marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
        .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
            IntentMarketplaceV0_3.MarketplacePublicPath
        ) ?? panic("Cannot borrow IntentMarketplaceV0_3")
    return marketplace.getOpenIntents()
}
`;

export const GET_INTENT_SCRIPT = `
import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"

access(all) fun main(intentID: UInt64): IntentMarketplaceV0_3.IntentView? {
    let marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
        .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
            IntentMarketplaceV0_3.MarketplacePublicPath
        ) ?? panic("Cannot borrow IntentMarketplaceV0_3")
    return marketplace.getIntent(intentID: intentID)
}
`;
