import ScheduledManagerV0_3 from "ScheduledManagerV0_3"

/// Update ScheduledManagerV0_3 to poll FlowIntentsComposerV4 instead of V3.
///
/// The selectors for getPendingIntents() and markPickedUp(uint256) are identical
/// in V4 — same function signatures are preserved. Only the address changes.
///
/// FlowIntentsComposerV4 address (Flow EVM mainnet, chainId 747):
///   0x9827e0A36D5B59fF7AF7E4eF05561eded7650441
///
/// NOTE: Intents created in ComposerV3 (0xb058B508c00e7ab94c33c0BA1d5ac87e5512b792)
///       will no longer be polled after this update. Manage V3 intents directly
///       via the V3 contract until they complete.
///
transaction(composerV4Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&ScheduledManagerV0_3.Admin>(
            from: ScheduledManagerV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow ScheduledManagerV0_3 Admin")

        // Update base composer address
        admin.setEVMContract(
            name: "composerV2",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV4Address,
                selector: []
            )
        )

        // Update getPendingIntents() — selector: 0x1b5c9baf (unchanged from V3)
        admin.setEVMContract(
            name: "composerV2_getPendingIntents",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV4Address,
                selector: [0x1b, 0x5c, 0x9b, 0xaf]
            )
        )

        // Update markPickedUp(uint256) — selector: 0x7b0472f0 (unchanged from V3)
        admin.setEVMContract(
            name: "composerV2_markPickedUp",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV4Address,
                selector: [0x7b, 0x04, 0x72, 0xf0]
            )
        )

        log("ScheduledManagerV0_3 EVM config updated to ComposerV4: ".concat(composerV4Address))
    }
}
