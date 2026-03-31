/// executeIntentV0_4.cdc
/// USER executes a BidSelected intent via IntentExecutorV0_4.executeIntent().
/// Key difference from V0_3: the USER signs this transaction, not the solver.
/// The user's COA is used for the cross-VM call.
/// Commission escrow is paid to the winning solver.
///
/// If deliverySide == CadenceVault: after the swap, tokens are bridged back
/// from the COA to a Cadence FungibleToken vault via FlowEVMBridge.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FungibleTokenMetadataViews from "FungibleTokenMetadataViews"
import ViewResolver from "ViewResolver"
import FlowToken from "FlowToken"
import IntentExecutorV0_4 from "IntentExecutorV0_4"
import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"
import BidManagerV0_4 from "BidManagerV0_4"
import FlowEVMBridge from "FlowEVMBridge"
import FlowEVMBridgeConfig from "FlowEVMBridgeConfig"
import FlowEVMBridgeUtils from "FlowEVMBridgeUtils"
import ScopedFTProviders from "ScopedFTProviders"

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

        // Read intent info for post-execution bridge
        let intent = IntentMarketplaceV0_4.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        self.deliverySide = intent.deliverySide.rawValue
        self.tokenOut = intent.tokenOut
    }

    execute {
        // Step 1: Execute the swap (principal → COA → ComposerV5 → swap → tokens in COA)
        IntentExecutorV0_4.executeIntent(
            intentID: intentID,
            userAddress: self.userAddress,
            coa: self.coa,
            userFlowVault: self.userFlowVault,
            solverFlowReceiver: self.solverFlowReceiver
        )

        // Step 2: If CadenceVault delivery, bridge output tokens from EVM to Cadence
        if self.deliverySide == 0 && self.tokenOut.length > 2 {
            // deliverySide 0 = CadenceVault
            // Construct the bridge vault type from the EVM token address
            // Pattern: A.<bridge_address>.EVMVMBridgedToken_<hex_addr>.Vault
            var tokenHex = self.tokenOut
            if tokenHex.length >= 2 && tokenHex.slice(from: 0, upTo: 2) == "0x" {
                tokenHex = tokenHex.slice(from: 2, upTo: tokenHex.length)
            }
            // Lowercase the hex
            let lowerChars: {String: String} = {
                "A":"a","B":"b","C":"c","D":"d","E":"e","F":"f"
            }
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

            // Check balance of output token on COA
            let evmAddr = self.coa.address()

            // Get token balance via EVM call (balanceOf)
            var balOfData: [UInt8] = [0x70, 0xa0, 0x82, 0x31] // balanceOf(address)
            // Pad address to 32 bytes
            var padIdx = 0
            while padIdx < 12 {
                balOfData.append(0)
                padIdx = padIdx + 1
            }
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

            // Parse token EVM address for the call
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
                to: tokenEvmAddr,
                data: balOfData,
                gasLimit: 50000,
                value: EVM.Balance(attoflow: 0)
            )

            // Decode UInt256 balance from result
            var tokenBalance: UInt256 = 0
            if balResult.status == EVM.Status.successful && balResult.data.length >= 32 {
                var bi = 0
                while bi < 32 {
                    tokenBalance = tokenBalance * 256 + UInt256(balResult.data[bi])
                    bi = bi + 1
                }
            }

            if tokenBalance > 0 {
                // Setup vault + fee provider for bridge
                let tokenContractAddress = FlowEVMBridgeUtils.getContractAddress(fromType: vaultType)
                    ?? panic("Could not get bridge contract address")
                let tokenContractName = FlowEVMBridgeUtils.getContractName(fromType: vaultType)
                    ?? panic("Could not get bridge contract name")

                let viewResolver = getAccount(tokenContractAddress).contracts.borrow<&{ViewResolver}>(name: tokenContractName)
                    ?? panic("Could not borrow ViewResolver for bridged token")
                let vaultData = viewResolver.resolveContractView(
                    resourceType: vaultType,
                    viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
                ) as! FungibleTokenMetadataViews.FTVaultData?
                    ?? panic("Could not resolve FTVaultData for bridged token")

                // Setup receiver vault if it doesn't exist
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
                    ?? panic("Could not borrow bridged token receiver vault")

                // Fee provider for bridge
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

                // Bridge tokens from EVM to Cadence
                let bridgedVault: @{FungibleToken.Vault} <- self.coa.withdrawTokens(
                    type: vaultType,
                    amount: tokenBalance,
                    feeProvider: &scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
                )

                receiver.deposit(from: <- bridgedVault)
                destroy scopedProvider

                log("Bridged ".concat(tokenBalance.toString()).concat(" tokens to Cadence vault"))
            }
        }

        log("V0_4 Intent ".concat(intentID.toString()).concat(" executed — commission paid to solver"))
    }
}
