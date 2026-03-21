/// registerSolver.cdc
/// Registers a solver agent by verifying their ERC-8004 token via COA staticCall.
/// The signer must own a COA and hold a valid AgentIdentityRegistry token.

import EVM from "EVM"
import SolverRegistry from "SolverRegistry"

transaction(evmAddress: String, tokenId: UInt256) {
    let coa: &EVM.CadenceOwnedAccount
    let signerAddress: Address

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        self.signerAddress = signer.address

        // Borrow COA (read-only is sufficient for dryCall/staticCall verification)
        self.coa = signer.storage
            .borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("Signer must have a Cadence Owned Account at /storage/evm")
    }

    execute {
        SolverRegistry.registerSolverWithAddress(
            coa: self.coa,
            cadenceAddress: self.signerAddress,
            evmAddress: evmAddress,
            tokenId: tokenId
        )
        log("Solver registered: ".concat(self.signerAddress.toString()))
    }
}
