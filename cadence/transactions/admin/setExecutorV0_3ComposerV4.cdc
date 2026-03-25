import IntentExecutorV0_3 from "IntentExecutorV0_3"

/// Update IntentExecutorV0_3 to use the latest FlowIntentsComposerV4 deployment.
///
/// FlowIntentsComposerV4 address (Flow EVM mainnet, chainId 747):
///   0x0F1D65b5F93eFB651EaC9E346D14c23CD12c4780
///
/// Updated in this deployment:
///   executeStrategyWithFunds(bytes,address) selector: 0x7661a94a
///   (previous: executeStrategyWithFunds(bytes) selector: 0x7954fae9)
///   executeSwapDirect(uint256,bytes,uint256) selector: 0x2fb08e6b
///
/// This transaction:
///   1. Updates the composer address in evmConfig for all composer keys.
///   2. Registers the new executeStrategyWithFunds(bytes,address) selector.
///
transaction(composerV4Address: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let admin = signer.storage.borrow<&IntentExecutorV0_3.Admin>(
            from: IntentExecutorV0_3.AdminStoragePath
        ) ?? panic("Cannot borrow IntentExecutorV0_3 Admin")

        // Update composer address (propagates to all composer_* keys)
        admin.setComposerAddress(addr: composerV4Address)

        // Register executeStrategyWithFunds(bytes,address) selector: 0x7661a94a
        // Computed via: cast sig "executeStrategyWithFunds(bytes,address)"
        admin.setEVMContract(
            name: "composer_executeStrategyWithFunds",
            config: IntentExecutorV0_3.EVMConfig(
                address: composerV4Address,
                selector: [0x76, 0x61, 0xa9, 0x4a]
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

        log("IntentExecutorV0_3 composer updated to V4 (with recipient sweep): ".concat(composerV4Address))
        log("executeStrategyWithFunds(bytes,address) selector registered: 0x7661a94a")
    }
}
