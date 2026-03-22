import SolverRegistryV0_2 from "SolverRegistryV0_2"

transaction(identityAddr: String, reputationAddr: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&SolverRegistryV0_2.Admin>(
            from: SolverRegistryV0_2.AdminStoragePath
        ) ?? panic("Cannot borrow SolverRegistryV0_2 Admin")
        admin.setIdentityRegistry(addr: identityAddr)
        admin.setReputationRegistry(addr: reputationAddr)
        log("SolverRegistryV0_2 EVM addresses set")
    }
}
