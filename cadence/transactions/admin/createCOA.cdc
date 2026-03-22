import EVM from "EVM"

transaction {
    prepare(signer: auth(Storage) &Account) {
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-coa, to: /storage/evm)
            log("COA created")
        } else {
            log("COA already exists")
        }
    }
}
