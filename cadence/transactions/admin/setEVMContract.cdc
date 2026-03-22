/// setEVMContract.cdc
/// NOTE: Requires V0_2 contracts (SolverRegistryV0_2, IntentExecutorV0_2).
/// V0_1 contracts do not implement the EVMConfig pattern.
/// Generic admin transaction to update an EVM contract address and/or selector
/// in any FlowIntents Cadence contract that uses the EVMConfig pattern.
///
/// This allows updating any EVM contract address or function selector without
/// redeploying the Cadence contract.
///
/// Parameters:
///   contractName: "SolverRegistryV0_1" or "IntentExecutorV0_1"
///   configName: e.g. "identityRegistry_ownerOf", "reputationRegistry_getMultiplier",
///               "composer", "composer_getIntentBalance"
///   evmAddress: The EVM contract address (hex string, with or without 0x prefix)
///   selector: The 4-byte function selector as [UInt8]

import SolverRegistryV0_1 from "SolverRegistryV0_1"
import IntentExecutorV0_1 from "IntentExecutorV0_1"

transaction(
    contractName: String,
    configName: String,
    evmAddress: String,
    selector: [UInt8]
) {
    prepare(signer: auth(BorrowValue) &Account) {
        if contractName == "SolverRegistryV0_1" {
            let admin = signer.storage.borrow<&SolverRegistryV0_1.Admin>(
                from: SolverRegistryV0_1.AdminStoragePath
            ) ?? panic("Cannot borrow SolverRegistryV0_1 Admin")
            let config = SolverRegistryV0_1.EVMConfig(
                address: evmAddress,
                selector: selector
            )
            admin.setEVMContract(name: configName, config: config)
            log("SolverRegistryV0_1 EVMConfig updated: ".concat(configName))
        } else if contractName == "IntentExecutorV0_1" {
            let admin = signer.storage.borrow<&IntentExecutorV0_1.Admin>(
                from: IntentExecutorV0_1.AdminStoragePath
            ) ?? panic("Cannot borrow IntentExecutorV0_1 Admin")
            let config = IntentExecutorV0_1.EVMConfig(
                address: evmAddress,
                selector: selector
            )
            admin.setEVMContract(name: configName, config: config)
            log("IntentExecutorV0_1 EVMConfig updated: ".concat(configName))
        } else {
            panic("Unknown contract: ".concat(contractName))
        }
    }
}
