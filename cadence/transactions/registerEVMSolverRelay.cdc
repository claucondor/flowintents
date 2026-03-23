/// registerEVMSolverRelay.cdc
/// Relayer (any Cadence account with COA) registers an EVM-only solver.
/// The EVM solver has no Cadence account — relayer acts on their behalf.
/// cadenceAddress is set to the relayer's address as proxy.
/// The actual solver identity is the evmAddress + tokenId (ERC-8004).

import EVM from "EVM"
import SolverRegistryV0_2 from "SolverRegistryV0_2"

transaction(solverEVMAddress: String, tokenId: UInt256) {
    let coa: &EVM.CadenceOwnedAccount
    let relayerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.relayerAddress = signer.address
        self.coa = signer.storage
            .borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("Relayer must have a COA at /storage/evm")
    }

    execute {
        SolverRegistryV0_2.registerSolverWithAddress(
            coa: self.coa,
            cadenceAddress: self.relayerAddress, // proxy — EVM solver has no Cadence account
            evmAddress: solverEVMAddress,
            tokenId: tokenId
        )
        log("EVM-only solver relayed: evmAddress=".concat(solverEVMAddress).concat(" tokenId=").concat(tokenId.toString()))
    }
}
