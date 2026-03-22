import ScheduledManagerV0_2 from "ScheduledManagerV0_2"

transaction(composerV2Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&ScheduledManagerV0_2.Admin>(
            from: ScheduledManagerV0_2.AdminStoragePath
        ) ?? panic("Cannot borrow ScheduledManagerV0_2 Admin")

        // Set composerV2 base address
        admin.setEVMContract(
            name: "composerV2",
            config: ScheduledManagerV0_2.EVMConfig(
                address: composerV2Address,
                selector: []
            )
        )

        // Set composerV2_getPendingIntents with same address
        admin.setEVMContract(
            name: "composerV2_getPendingIntents",
            config: ScheduledManagerV0_2.EVMConfig(
                address: composerV2Address,
                selector: [0x1b, 0x5c, 0x9b, 0xaf]
            )
        )

        // Set composerV2_markPickedUp with same address
        admin.setEVMContract(
            name: "composerV2_markPickedUp",
            config: ScheduledManagerV0_2.EVMConfig(
                address: composerV2Address,
                selector: [0x7b, 0x04, 0x72, 0xf0]
            )
        )

        log("ScheduledManagerV0_2 EVM config set")
    }
}
