import SolverRegistryV0_1 from "SolverRegistryV0_1"

transaction(identityAddr: String, reputationAddr: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&SolverRegistryV0_1.Admin>(
            from: SolverRegistryV0_1.AdminStoragePath
        ) ?? panic("Cannot borrow Admin")
        admin.setIdentityRegistry(addr: identityAddr)
        admin.setReputationRegistry(addr: reputationAddr)
        log("SolverRegistry EVM addresses set")
    }
}
