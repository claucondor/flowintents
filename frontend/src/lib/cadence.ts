export const CREATE_SWAP_INTENT_TX = `
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentMarketplaceV0_3 from 0xIntentMarketplaceV0_3

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
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentMarketplaceV0_3 from 0xIntentMarketplaceV0_3

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
import BidManagerV0_3 from 0xBidManagerV0_3

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
import BidManagerV0_3 from 0xBidManagerV0_3

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
import EVM from 0xEVM
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentExecutorV0_3 from 0xIntentExecutorV0_3

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
import IntentMarketplaceV0_3 from 0xIntentMarketplaceV0_3

access(all) fun main(): [UInt64] {
    let marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
        .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
            IntentMarketplaceV0_3.MarketplacePublicPath
        ) ?? panic("Cannot borrow IntentMarketplaceV0_3")
    return marketplace.getOpenIntents()
}
`;

export const GET_INTENT_SCRIPT = `
import IntentMarketplaceV0_3 from 0xIntentMarketplaceV0_3

access(all) fun main(intentID: UInt64): IntentMarketplaceV0_3.IntentView? {
    let marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
        .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
            IntentMarketplaceV0_3.MarketplacePublicPath
        ) ?? panic("Cannot borrow IntentMarketplaceV0_3")
    return marketplace.getIntent(intentID: intentID)
}
`;

// =============================================================================
// V0_4 Transaction Templates — User-Executed Intent Model
// =============================================================================

export const CREATE_SWAP_INTENT_V04_TX = `
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentMarketplaceV0_4 from 0xIntentMarketplaceV0_4

transaction(
    principalAmount: UFix64,
    tokenOut: String,
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

        self.commissionEscrowVault <- flowVault.withdraw(amount: commissionEscrowAmount) as! @FlowToken.Vault
        self.signerAddress = signer.address
    }

    execute {
        let intentID = self.marketplace.createSwapIntent(
            ownerAddress: self.signerAddress,
            principalAmount: principalAmount,
            tokenOut: tokenOut,
            deliverySide: deliverySide,
            deliveryAddress: deliveryAddress,
            durationDays: durationDays,
            expiryBlock: expiryBlock,
            commissionEscrowVault: <- self.commissionEscrowVault
        )
        log("V0_4 SWAP Intent created with ID: ".concat(intentID.toString()))
    }
}
`;

export const CREATE_YIELD_INTENT_V04_TX = `
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentMarketplaceV0_4 from 0xIntentMarketplaceV0_4

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
`;

export const SUBMIT_BID_V04_TX = `
import BidManagerV0_4 from 0xBidManagerV0_4

transaction(
    intentID: UInt64,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    maxGasBid: UFix64,
    strategy: String,
    encodedBatch: [UInt8]
) {
    let solverAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.solverAddress = signer.address
    }

    execute {
        let bidID = BidManagerV0_4.submitBid(
            intentID: intentID,
            solverAddress: self.solverAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch
        )
        log("V0_4 Bid ".concat(bidID.toString()).concat(" submitted for intent ").concat(intentID.toString()))
    }
}
`;

export const SELECT_WINNER_V04_TX = `
import BidManagerV0_4 from 0xBidManagerV0_4

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_4.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("V0_4 Winner selected for intent ".concat(intentID.toString()))
    }
}
`;

export const EXECUTE_INTENT_V04_TX = `
import EVM from 0xEVM
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentExecutorV0_4 from 0xIntentExecutorV0_4
import BidManagerV0_4 from 0xBidManagerV0_4

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let userAddress: Address
    let userFlowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let solverFlowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.userAddress = signer.address

        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("User must have a COA at /storage/evm")

        self.userFlowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow user FlowToken vault")

        let winningBid = BidManagerV0_4.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")
        let solverAddress = winningBid.solverAddress

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
        log("V0_4 Intent ".concat(intentID.toString()).concat(" executed by user"))
    }
}
`;

export const CANCEL_INTENT_V04_TX = `
import FungibleToken from 0xFungibleToken
import FlowToken from 0xFlowToken
import IntentMarketplaceV0_4 from 0xIntentMarketplaceV0_4

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
        log("V0_4 Intent ".concat(intentID.toString()).concat(" cancelled"))
    }
}
`;
