import IntentExecutorV0_3 from "IntentExecutorV0_3"

transaction(composerAddr: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_3.Admin>(
            from: IntentExecutorV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_3 Admin")
        admin.setComposerAddress(addr: composerAddr)
        log("IntentExecutorV0_3 composer address set")
    }
}
