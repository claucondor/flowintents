import ScheduledManagerV0_3 from "ScheduledManagerV0_3"

transaction(composerV2Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&ScheduledManagerV0_3.Admin>(
            from: ScheduledManagerV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow ScheduledManagerV0_3 Admin")

        // Set composerV2 base address
        admin.setEVMContract(
            name: "composerV2",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV2Address,
                selector: []
            )
        )

        // Set composerV2_getPendingIntents — selector: getPendingIntents()
        admin.setEVMContract(
            name: "composerV2_getPendingIntents",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV2Address,
                selector: [0x1b, 0x5c, 0x9b, 0xaf]
            )
        )

        // Set composerV2_markPickedUp — selector: markPickedUp(uint256)
        admin.setEVMContract(
            name: "composerV2_markPickedUp",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV2Address,
                selector: [0x7b, 0x04, 0x72, 0xf0]
            )
        )

        log("ScheduledManagerV0_3 EVM config set to: ".concat(composerV2Address))
    }
}
