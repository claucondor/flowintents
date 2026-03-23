import IntentExecutorV0_3 from "IntentExecutorV0_3"

/// Update IntentExecutorV0_3 to use FlowIntentsComposerV4 instead of V3.
///
/// FlowIntentsComposerV4 address (Flow EVM mainnet, chainId 747):
///   0x9827e0A36D5B59fF7AF7E4eF05561eded7650441
///
/// New in V4:
///   executeStrategyWithFunds(bytes) selector: 0x7954fae9
///   executeSwapDirect(uint256,bytes,uint256) selector: 0x2fb08e6b
///
/// This transaction:
///   1. Updates the composer address in evmConfig for all composer keys.
///   2. Registers the executeStrategyWithFunds selector.
///
transaction(composerV4Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_3.Admin>(
            from: IntentExecutorV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_3 Admin")

        // Update composer address (propagates to all composer_* keys)
        admin.setComposerAddress(addr: composerV4Address)

        // Register executeStrategyWithFunds(bytes) selector: 0x7954fae9
        // Computed via: cast sig "executeStrategyWithFunds(bytes)"
        admin.setEVMContract(
            name: "composer_executeStrategyWithFunds",
            config: IntentExecutorV0_3.EVMConfig(
                address: composerV4Address,
                selector: [0x79, 0x54, 0xfa, 0xe9]
            )
        )

        // Register getIntentBalance(uint256) selector: 0x9507d39a
        // Computed via: cast sig "getIntentBalance(uint256)"
        admin.setEVMContract(
            name: "composer_getIntentBalance",
            config: IntentExecutorV0_3.EVMConfig(
                address: composerV4Address,
                selector: [0x95, 0x07, 0xd3, 0x9a]
            )
        )

        log("IntentExecutorV0_3 composer updated to V4: ".concat(composerV4Address))
        log("executeStrategyWithFunds selector registered: 0x7954fae9")
    }
}
