/// relayEVMIntent.cdc
/// Relays an EVM-originated intent from EVMBidRelay.sol into IntentMarketplaceV0_3.
///
/// Flow:
///   1. COA calls EVMBidRelay.releaseToCOA(evmIntentId) via coa.call()
///      → FLOW (principal + gasEscrow) arrives at the COA's EVM balance.
///   2. coa.withdraw(balance: ...) bridges FLOW from EVM to a Cadence FlowToken.Vault.
///   3. The vault is split: principalAmount stays in vault, gasEscrowAmount is split off.
///   4. IntentMarketplaceV0_3.createYieldIntent() or createSwapIntent() creates a native
///      Cadence intent with principalSide = cadence.
///
/// After this tx the intent is indistinguishable from a Cadence-originated intent.
/// The relayer account's address is used as the intent ownerAddress.
///
/// Parameters:
///   evmIntentId         — ID in EVMBidRelay.sol (UInt64)
///   intentType          — 0 = yield, 1 = swap
///   targetAPY           — For yield: target APY as UFix64 (e.g. 5.0 = 5%)
///   minAmountOut        — For swap: minimum output as UFix64
///   maxFeeBPS           — Max fee in basis points
///   durationDays        — Duration in days
///   expiryBlock         — Block number when intent expires
///   principalAmount     — Principal FLOW as UFix64 (must match EVMIntent.amount / 1e10)
///   gasEscrowAmount     — Gas escrow FLOW as UFix64 (must match EVMIntent.gasEscrow / 1e10)
///   recipientEVMAddress — EVM creator address (from EVMBidRelay.EVMIntentSubmitted event).
///                         Recorded here for off-chain indexing only; pass it to
///                         IntentExecutorV0_3.executeIntentV2() at execution time so output
///                         tokens are routed back to the original EVM wallet.

import EVM from "EVM"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"

transaction(
    evmIntentId:         UInt64,
    intentType:          UInt8,
    targetAPY:           UFix64,
    minAmountOut:        UFix64,
    maxFeeBPS:           UInt64,
    durationDays:        UInt64,
    expiryBlock:         UInt64,
    principalAmount:     UFix64,
    gasEscrowAmount:     UFix64,
    recipientEVMAddress: String?
) {
    let coa: auth(EVM.Call, EVM.Withdraw) &EVM.CadenceOwnedAccount
    let ownerAddress: Address
    let marketplace: &IntentMarketplaceV0_3.Marketplace

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.ownerAddress = signer.address

        self.coa = signer.storage
            .borrow<auth(EVM.Call, EVM.Withdraw) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("Relayer must have a COA at /storage/evm with EVM.Call + EVM.Withdraw entitlements")

        self.marketplace = getAccount(IntentMarketplaceV0_3.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
                IntentMarketplaceV0_3.MarketplacePublicPath
            ) ?? panic("Cannot borrow IntentMarketplaceV0_3.Marketplace")
    }

    execute {
        // ---------------------------------------------------------------
        // Step 1: Build calldata for EVMBidRelay.releaseToCOA(uint256)
        //
        // Selector: keccak256("releaseToCOA(uint256)")[0:4] = 0x6443f052
        // (Verify: cast sig "releaseToCOA(uint256)" → 0x6443f052)
        // ABI layout: 4-byte selector + 32-byte uint256 (big-endian, zero-padded)
        // ---------------------------------------------------------------
        var calldata: [UInt8] = [0x64, 0x43, 0xf0, 0x52]

        // Encode evmIntentId as uint256 big-endian (32 bytes, zero-padded left)
        var idBytes: [UInt8] = []
        var tmp: UInt64 = evmIntentId
        var j: Int = 0
        while j < 32 {
            idBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(idBytes)

        // ---------------------------------------------------------------
        // Step 2: Parse EVMBidRelay address hex string → EVM.EVMAddress
        //
        // EVMBidRelay deployed at: 0x0f58eA537424C261FB55B45B77e5a25823077E05
        // (Flow EVM mainnet chainId 747 — update if redeployed)
        // ---------------------------------------------------------------
        let evmBidRelayHex = "0f58eA537424C261FB55B45B77e5a25823077E05"

        // Inline hex-to-bytes conversion (no helper function — Cadence transactions
        // do not support top-level fun declarations outside the transaction block)
        var addrBytes: [UInt8] = []
        var k: Int = 0
        while k < 40 {
            let highChar = evmBidRelayHex.slice(from: k,     upTo: k + 1)
            let lowChar  = evmBidRelayHex.slice(from: k + 1, upTo: k + 2)

            var high: UInt8 = 0
            switch highChar {
                case "0": high = 0
                case "1": high = 1
                case "2": high = 2
                case "3": high = 3
                case "4": high = 4
                case "5": high = 5
                case "6": high = 6
                case "7": high = 7
                case "8": high = 8
                case "9": high = 9
                case "a": high = 10
                case "A": high = 10
                case "b": high = 11
                case "B": high = 11
                case "c": high = 12
                case "C": high = 12
                case "d": high = 13
                case "D": high = 13
                case "e": high = 14
                case "E": high = 14
                case "f": high = 15
                case "F": high = 15
            }

            var low: UInt8 = 0
            switch lowChar {
                case "0": low = 0
                case "1": low = 1
                case "2": low = 2
                case "3": low = 3
                case "4": low = 4
                case "5": low = 5
                case "6": low = 6
                case "7": low = 7
                case "8": low = 8
                case "9": low = 9
                case "a": low = 10
                case "A": low = 10
                case "b": low = 11
                case "B": low = 11
                case "c": low = 12
                case "C": low = 12
                case "d": low = 13
                case "D": low = 13
                case "e": low = 14
                case "E": low = 14
                case "f": low = 15
                case "F": low = 15
            }

            addrBytes.append((high << 4) | low)
            k = k + 2
        }

        let relayAddr = EVM.EVMAddress(bytes: [
            addrBytes[0],  addrBytes[1],  addrBytes[2],  addrBytes[3],  addrBytes[4],
            addrBytes[5],  addrBytes[6],  addrBytes[7],  addrBytes[8],  addrBytes[9],
            addrBytes[10], addrBytes[11], addrBytes[12], addrBytes[13], addrBytes[14],
            addrBytes[15], addrBytes[16], addrBytes[17], addrBytes[18], addrBytes[19]
        ])

        // ---------------------------------------------------------------
        // Step 3: Call releaseToCOA — EVMBidRelay sends FLOW to COA's EVM address
        // ---------------------------------------------------------------
        let callResult = self.coa.call(
            to: relayAddr,
            data: calldata,
            gasLimit: 100000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(
            callResult.status == EVM.Status.successful,
            message: "EVMBidRelay.releaseToCOA() failed — check evmIntentId and release status"
        )

        // ---------------------------------------------------------------
        // Step 4: Convert UFix64 → attoFLOW and withdraw from COA's EVM balance
        //
        // UFix64 has 8 decimal places; attoFLOW has 18. Conversion factor = 10^10.
        // 1.0 FLOW → UInt(1.0 × 1e8) = 100_000_000 → × 10^10 = 10^18 attoFLOW ✓
        // (same pattern as IntentExecutorV0_3.cdc)
        // ---------------------------------------------------------------
        let totalAmount: UFix64 = principalAmount + gasEscrowAmount
        let totalAttoflow: UInt = UInt(totalAmount * 100_000_000.0) * 10_000_000_000

        let bridgedVault <- self.coa.withdraw(balance: EVM.Balance(attoflow: totalAttoflow))
        let flowVault <- bridgedVault as! @FlowToken.Vault

        // ---------------------------------------------------------------
        // Step 5: Split the vault — extract gas escrow, leave principal
        // ---------------------------------------------------------------
        let gasEscrowVault <- (flowVault.withdraw(amount: gasEscrowAmount) as! @FlowToken.Vault)
        // flowVault now holds principalAmount only

        // ---------------------------------------------------------------
        // Step 6: Create the Cadence intent in IntentMarketplaceV0_3
        // ---------------------------------------------------------------
        if intentType == 0 {
            // Yield intent
            let cadenceIntentId = self.marketplace.createYieldIntent(
                ownerAddress: self.ownerAddress,
                vault: <- (flowVault as @{FungibleToken.Vault}),
                targetAPY: targetAPY,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                gasEscrowVault: <- gasEscrowVault
            )
            log(
                "EVM intent "
                    .concat(evmIntentId.toString())
                    .concat(" relayed → Cadence yield intent #")
                    .concat(cadenceIntentId.toString())
            )
        } else if intentType == 1 {
            // Swap intent
            let cadenceIntentId = self.marketplace.createSwapIntent(
                ownerAddress: self.ownerAddress,
                vault: <- (flowVault as @{FungibleToken.Vault}),
                minAmountOut: minAmountOut,
                maxFeeBPS: maxFeeBPS,
                durationDays: durationDays,
                expiryBlock: expiryBlock,
                gasEscrowVault: <- gasEscrowVault
            )
            log(
                "EVM intent "
                    .concat(evmIntentId.toString())
                    .concat(" relayed → Cadence swap intent #")
                    .concat(cadenceIntentId.toString())
            )
        } else {
            // Consume vaults to avoid resource loss before panicking
            destroy flowVault
            destroy gasEscrowVault
            panic("relayEVMIntent: unknown intentType ".concat(intentType.toString()))
        }
    }
}
