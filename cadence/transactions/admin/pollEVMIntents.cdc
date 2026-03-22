import ScheduledManagerV0_2 from "ScheduledManagerV0_2"
import EVM from "EVM"

transaction {
    prepare(signer: auth(Storage, BorrowValue) &Account) {
        let admin = signer.storage.borrow<&ScheduledManagerV0_2.Admin>(
            from: ScheduledManagerV0_2.AdminStoragePath
        ) ?? panic("Cannot borrow ScheduledManagerV0_2 Admin")

        let coa = signer.storage.borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("No COA found — create one first")

        admin.pollEVMIntents(coaRef: coa)
        log("EVM intent polling complete")
    }
}
