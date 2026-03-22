import IntentExecutorV0_1 from "IntentExecutorV0_1"

transaction(composerAddr: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_1.Admin>(
            from: IntentExecutorV0_1.AdminStoragePath
        ) ?? panic("Cannot borrow Admin")
        admin.setComposerAddress(addr: composerAddr)
        log("Executor composer address set")
    }
}
