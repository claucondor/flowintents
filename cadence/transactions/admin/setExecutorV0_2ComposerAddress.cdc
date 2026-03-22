import IntentExecutorV0_2 from "IntentExecutorV0_2"

transaction(composerAddr: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_2.Admin>(
            from: IntentExecutorV0_2.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_2 Admin")
        admin.setComposerAddress(addr: composerAddr)
        log("IntentExecutorV0_2 composer address set")
    }
}
