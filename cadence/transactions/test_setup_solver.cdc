/// test_setup_solver.cdc
/// TEST ONLY: Sets up a solver on emulator by deploying mock EVM contracts
/// that always return valid responses for ownerOf and getMultiplier.

import EVM from "EVM"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

transaction(evmAddress: String, tokenId: UInt256) {
    let coa: auth(EVM.Call, EVM.Deploy) &EVM.CadenceOwnedAccount
    let signerAddress: Address
    let identityHex: String
    let reputationHex: String

    prepare(signer: auth(Storage, SaveValue, BorrowValue, Capabilities) &Account) {
        self.signerAddress = signer.address

        // Create COA if it doesn't exist
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let newCoa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-newCoa, to: /storage/evm)
        }
        self.coa = signer.storage.borrow<auth(EVM.Call, EVM.Deploy) &EVM.CadenceOwnedAccount>(from: /storage/evm)!

        // Deploy mock identity registry that returns 1 for any call
        // Runtime code: 600160005260206000F3 (10 bytes)
        let deployCode: [UInt8] = [
            0x69,
            0x60, 0x01, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3,
            0x60, 0x00, 0x52,
            0x60, 0x0a, 0x60, 0x16, 0xF3
        ]
        let identityResult = self.coa.deploy(code: deployCode, gasLimit: 200000, value: EVM.Balance(attoflow: 0))
        assert(identityResult.status == EVM.Status.successful, message: "Mock identity deploy failed")
        let identityAddr = identityResult.deployedContract!

        // Deploy mock reputation registry that returns 10000 for any call
        // Runtime: 61271060005260206000F3 (12 bytes)
        let deployCodeRep: [UInt8] = [
            0x6B,
            0x61, 0x27, 0x10, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3,
            0x60, 0x00, 0x52,
            0x60, 0x0c, 0x60, 0x14, 0xF3
        ]
        let reputationResult = self.coa.deploy(code: deployCodeRep, gasLimit: 200000, value: EVM.Balance(attoflow: 0))
        assert(reputationResult.status == EVM.Status.successful, message: "Mock reputation deploy failed")
        let reputationAddr = reputationResult.deployedContract!

        // Convert EVM addresses to hex strings inline
        let hexChars = "0123456789abcdef"
        var idHex = "0x"
        for byte in identityAddr.bytes {
            let high = byte >> 4
            let low = byte & 0x0f
            idHex = idHex.concat(hexChars.slice(from: Int(high), upTo: Int(high) + 1))
            idHex = idHex.concat(hexChars.slice(from: Int(low), upTo: Int(low) + 1))
        }
        self.identityHex = idHex

        var repHex = "0x"
        for byte in reputationAddr.bytes {
            let high = byte >> 4
            let low = byte & 0x0f
            repHex = repHex.concat(hexChars.slice(from: Int(high), upTo: Int(high) + 1))
            repHex = repHex.concat(hexChars.slice(from: Int(low), upTo: Int(low) + 1))
        }
        self.reputationHex = repHex

        log("Mock identity registry: ".concat(self.identityHex))
        log("Mock reputation registry: ".concat(self.reputationHex))

        // Set registry addresses via admin
        let admin = signer.storage.borrow<&SolverRegistryV0_1.Admin>(
            from: SolverRegistryV0_1.AdminStoragePath
        ) ?? panic("Cannot borrow SolverRegistryV0_1 Admin")
        admin.setIdentityRegistry(addr: self.identityHex)
        admin.setReputationRegistry(addr: self.reputationHex)
    }

    execute {
        SolverRegistryV0_1.registerSolverWithAddress(
            coa: self.coa,
            cadenceAddress: self.signerAddress,
            evmAddress: evmAddress,
            tokenId: tokenId
        )
        log("Solver registered: ".concat(self.signerAddress.toString()))
    }
}
