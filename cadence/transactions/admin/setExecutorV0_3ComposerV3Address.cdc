import IntentExecutorV0_3 from "IntentExecutorV0_3"

transaction(composerV3Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_3.Admin>(
            from: IntentExecutorV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_3 Admin")
        admin.setComposerAddress(addr: composerV3Address)
        log("IntentExecutorV0_3 composer updated to V3: ".concat(composerV3Address))
    }
}
