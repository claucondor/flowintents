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
import FungibleTokenMetadataViews from 0xFungibleTokenMetadataViews
import ViewResolver from 0xViewResolver
import FlowToken from 0xFlowToken
import IntentExecutorV0_4 from 0xIntentExecutorV0_4
import IntentMarketplaceV0_4 from 0xIntentMarketplaceV0_4
import BidManagerV0_4 from 0xBidManagerV0_4
import FlowEVMBridge from 0xFlowEVMBridge
import FlowEVMBridgeConfig from 0xFlowEVMBridgeConfig
import FlowEVMBridgeUtils from 0xFlowEVMBridgeUtils
import ScopedFTProviders from 0xScopedFTProviders

transaction(intentID: UInt64) {
    let coa: auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount
    let userAddress: Address
    let userFlowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let solverFlowReceiver: &{FungibleToken.Receiver}
    let deliverySide: UInt8
    let tokenOut: String
    let signer: auth(Storage, BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account

    prepare(acct: auth(Storage, BorrowValue, CopyValue, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account) {
        self.userAddress = acct.address
        self.signer = acct

        self.coa = acct.storage
            .borrow<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("User must have a COA at /storage/evm")

        self.userFlowVault = acct.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow user FlowToken vault")

        let winningBid = BidManagerV0_4.getWinningBid(intentID: intentID)
            ?? panic("No winning bid found for intent")

        self.solverFlowReceiver = getAccount(winningBid.solverAddress)
            .capabilities.borrow<&{FungibleToken.Receiver}>(
                /public/flowTokenReceiver
            ) ?? panic("Cannot borrow solver FlowToken receiver")

        let intent = IntentMarketplaceV0_4.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        self.deliverySide = intent.deliverySide.rawValue
        self.tokenOut = intent.tokenOut
    }

    execute {
        IntentExecutorV0_4.executeIntent(
            intentID: intentID,
            userAddress: self.userAddress,
            coa: self.coa,
            userFlowVault: self.userFlowVault,
            solverFlowReceiver: self.solverFlowReceiver
        )

        if self.deliverySide == 0 {
            var tokenHex = self.tokenOut
            if tokenHex.length >= 2 && tokenHex.slice(from: 0, upTo: 2) == "0x" {
                tokenHex = tokenHex.slice(from: 2, upTo: tokenHex.length)
            }
            let lowerChars: {String: String} = {"A":"a","B":"b","C":"c","D":"d","E":"e","F":"f"}
            var lowerHex = ""
            var ci = 0
            while ci < tokenHex.length {
                let ch = tokenHex.slice(from: ci, upTo: ci + 1)
                lowerHex = lowerHex.concat(lowerChars[ch] ?? ch)
                ci = ci + 1
            }
            let vaultIdentifier = "A.1e4aa0b87d10b141.EVMVMBridgedToken_".concat(lowerHex).concat(".Vault")
            let vaultType = CompositeType(vaultIdentifier)
                ?? panic("Could not construct vault type: ".concat(vaultIdentifier))

            let evmAddr = self.coa.address()
            var balOfData: [UInt8] = [0x70, 0xa0, 0x82, 0x31]
            var padIdx = 0
            while padIdx < 12 { balOfData.append(0); padIdx = padIdx + 1 }
            let addrBytes = evmAddr.bytes
            balOfData.append(addrBytes[0]);  balOfData.append(addrBytes[1])
            balOfData.append(addrBytes[2]);  balOfData.append(addrBytes[3])
            balOfData.append(addrBytes[4]);  balOfData.append(addrBytes[5])
            balOfData.append(addrBytes[6]);  balOfData.append(addrBytes[7])
            balOfData.append(addrBytes[8]);  balOfData.append(addrBytes[9])
            balOfData.append(addrBytes[10]); balOfData.append(addrBytes[11])
            balOfData.append(addrBytes[12]); balOfData.append(addrBytes[13])
            balOfData.append(addrBytes[14]); balOfData.append(addrBytes[15])
            balOfData.append(addrBytes[16]); balOfData.append(addrBytes[17])
            balOfData.append(addrBytes[18]); balOfData.append(addrBytes[19])

            // Parse EVM address inline (can't use IntentExecutorV0_4.parseEVMAddress — access(self))
            var th = self.tokenOut
            if th.length >= 2 && th.slice(from: 0, upTo: 2) == "0x" { th = th.slice(from: 2, upTo: th.length) }
            while th.length < 40 { th = "0".concat(th) }
            let hc: {String: UInt8} = {"0":0,"1":1,"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"a":10,"b":11,"c":12,"d":13,"e":14,"f":15,"A":10,"B":11,"C":12,"D":13,"E":14,"F":15}
            var ab: [UInt8] = []
            var ai = 0
            while ai < 40 {
                let hi = hc[th.slice(from: ai, upTo: ai+1)] ?? 0
                let lo = hc[th.slice(from: ai+1, upTo: ai+2)] ?? 0
                ab.append((hi << 4) | lo)
                ai = ai + 2
            }
            let tokenEvmAddr = EVM.EVMAddress(bytes: [ab[0],ab[1],ab[2],ab[3],ab[4],ab[5],ab[6],ab[7],ab[8],ab[9],ab[10],ab[11],ab[12],ab[13],ab[14],ab[15],ab[16],ab[17],ab[18],ab[19]])
            let balResult = self.coa.call(
                to: tokenEvmAddr, data: balOfData, gasLimit: 50000,
                value: EVM.Balance(attoflow: 0)
            )

            var tokenBalance: UInt256 = 0
            if balResult.status == EVM.Status.successful && balResult.data.length >= 32 {
                var bi = 0
                while bi < 32 { tokenBalance = tokenBalance * 256 + UInt256(balResult.data[bi]); bi = bi + 1 }
            }

            if tokenBalance > 0 {
                let tokenContractAddress = FlowEVMBridgeUtils.getContractAddress(fromType: vaultType)
                    ?? panic("Could not get bridge contract address")
                let tokenContractName = FlowEVMBridgeUtils.getContractName(fromType: vaultType)
                    ?? panic("Could not get bridge contract name")
                let viewResolver = getAccount(tokenContractAddress).contracts.borrow<&{ViewResolver}>(name: tokenContractName)
                    ?? panic("Could not borrow ViewResolver")
                let vaultData = viewResolver.resolveContractView(
                    resourceType: vaultType,
                    viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
                ) as! FungibleTokenMetadataViews.FTVaultData?
                    ?? panic("Could not resolve FTVaultData")

                if self.signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath) == nil {
                    self.signer.storage.save(<- vaultData.createEmptyVault(), to: vaultData.storagePath)
                    self.signer.capabilities.unpublish(vaultData.receiverPath)
                    self.signer.capabilities.unpublish(vaultData.metadataPath)
                    self.signer.capabilities.publish(
                        self.signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(vaultData.storagePath),
                        at: vaultData.receiverPath
                    )
                    self.signer.capabilities.publish(
                        self.signer.capabilities.storage.issue<&{FungibleToken.Vault}>(vaultData.storagePath),
                        at: vaultData.metadataPath
                    )
                }
                let receiver = self.signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath)
                    ?? panic("Could not borrow receiver vault")

                let approxFee = FlowEVMBridgeUtils.calculateBridgeFee(bytes: 0)
                if self.signer.storage.type(at: FlowEVMBridgeConfig.providerCapabilityStoragePath) == nil {
                    let providerCap = self.signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(
                        /storage/flowTokenVault
                    )
                    self.signer.storage.save(providerCap, to: FlowEVMBridgeConfig.providerCapabilityStoragePath)
                }
                let providerCapCopy = self.signer.storage.copy<Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>>(
                    from: FlowEVMBridgeConfig.providerCapabilityStoragePath
                ) ?? panic("Invalid provider capability")
                let providerFilter = ScopedFTProviders.AllowanceFilter(approxFee)
                let scopedProvider <- ScopedFTProviders.createScopedFTProvider(
                    provider: providerCapCopy,
                    filters: [ providerFilter ],
                    expiration: getCurrentBlock().timestamp + 1.0
                )

                let bridgedVault: @{FungibleToken.Vault} <- self.coa.withdrawTokens(
                    type: vaultType,
                    amount: tokenBalance,
                    feeProvider: &scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
                )
                receiver.deposit(from: <- bridgedVault)
                destroy scopedProvider
            }
        }
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
