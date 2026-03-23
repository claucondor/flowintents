import ScheduledManagerV0_3 from "ScheduledManagerV0_3"

/// Update ScheduledManagerV0_3 to poll FlowIntentsComposerV3 instead of V2.
/// The selectors are identical — same getPendingIntents() and markPickedUp(uint256)
/// function signatures are preserved in V3.
///
/// FlowIntentsComposerV3 address (Flow EVM mainnet, chainId 747):
///   0xb058B508c00e7ab94c33c0BA1d5ac87e5512b792
///
/// NOTE: Intent #1 (created in ComposerV2 at 0x37c6F3A5F7C27274112eB903242cD9a82239F5B9)
///       is still valid on V2. After this update, ScheduledManager will poll V3 only.
///       V2 intent #1 must be managed directly via the V2 contract until completed.
transaction(composerV3Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&ScheduledManagerV0_3.Admin>(
            from: ScheduledManagerV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow ScheduledManagerV0_3 Admin")

        // Set composerV3 base address
        admin.setEVMContract(
            name: "composerV2",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV3Address,
                selector: []
            )
        )

        // Set composerV3_getPendingIntents — selector: getPendingIntents()
        // selector bytes: keccak256("getPendingIntents()")[0:4] = 0x1b5c9baf
        admin.setEVMContract(
            name: "composerV2_getPendingIntents",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV3Address,
                selector: [0x1b, 0x5c, 0x9b, 0xaf]
            )
        )

        // Set composerV3_markPickedUp — selector: markPickedUp(uint256)
        // selector bytes: keccak256("markPickedUp(uint256)")[0:4] = 0x7b0472f0
        admin.setEVMContract(
            name: "composerV2_markPickedUp",
            config: ScheduledManagerV0_3.EVMConfig(
                address: composerV3Address,
                selector: [0x7b, 0x04, 0x72, 0xf0]
            )
        )

        log("ScheduledManagerV0_3 EVM config updated to ComposerV3: ".concat(composerV3Address))
    }
}
