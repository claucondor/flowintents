/// test_setup_executor.cdc
/// TEST ONLY: Deploy mock EVM composer and set it on IntentExecutorV0_2.

import EVM from "EVM"
import IntentExecutorV0_2 from "IntentExecutorV0_2"

transaction {
    prepare(signer: auth(Storage, BorrowValue) &Account) {
        let coa = signer.storage.borrow<auth(EVM.Call, EVM.Deploy) &EVM.CadenceOwnedAccount>(from: /storage/evm)!

        // Deploy mock composer that returns success for any call
        // Runtime: 600160005260206000F3 (returns 1)
        let deployCode: [UInt8] = [
            0x69,
            0x60, 0x01, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3,
            0x60, 0x00, 0x52,
            0x60, 0x0a, 0x60, 0x16, 0xF3
        ]
        let result = coa.deploy(code: deployCode, gasLimit: 200000, value: EVM.Balance(attoflow: 0))
        assert(result.status == EVM.Status.successful, message: "Mock composer deploy failed")
        let composerAddr = result.deployedContract!

        // Convert to hex
        let hexChars = "0123456789abcdef"
        var hex = "0x"
        for byte in composerAddr.bytes {
            let high = byte >> 4
            let low = byte & 0x0f
            hex = hex.concat(hexChars.slice(from: Int(high), upTo: Int(high) + 1))
            hex = hex.concat(hexChars.slice(from: Int(low), upTo: Int(low) + 1))
        }

        log("Mock composer deployed at: ".concat(hex))

        // Set composer address on executor
        let admin = signer.storage.borrow<&IntentExecutorV0_2.Admin>(
            from: IntentExecutorV0_2.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_2 Admin")
        admin.setComposerAddress(addr: hex)
        log("Composer address set on IntentExecutorV0_2")
    }

    execute {}
}
