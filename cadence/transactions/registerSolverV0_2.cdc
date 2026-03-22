/// registerSolverV0_2.cdc
/// Registers a solver agent by verifying their ERC-8004 token via EVM.dryCall (staticCall).
/// Uses SolverRegistryV0_2.registerSolverWithAddress().

import EVM from "EVM"
import SolverRegistryV0_2 from "SolverRegistryV0_2"

transaction(evmAddress: String, tokenId: UInt256) {
    let coa: &EVM.CadenceOwnedAccount
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.signerAddress = signer.address

        self.coa = signer.storage
            .borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("Signer must have a Cadence Owned Account at /storage/evm")
    }

    execute {
        SolverRegistryV0_2.registerSolverWithAddress(
            coa: self.coa,
            cadenceAddress: self.signerAddress,
            evmAddress: evmAddress,
            tokenId: tokenId
        )
        log("Solver registered via V0_2: ".concat(self.signerAddress.toString()))
    }
}
