/// checkPositions.cdc
/// Manually triggers a position check (without Forte scheduler).
/// Useful during development; in production use the ScheduledManager Handler.

import FlowTransactionScheduler from "FlowTransactionScheduler"
import FlowToken from "FlowToken"
import FungibleToken from "FungibleToken"
import ScheduledManager from "ScheduledManager"

transaction(
    targetTimestamp: UFix64,
    feeAmount: UFix64,
    intentIDs: [UInt64]?
) {
    prepare(signer: auth(Storage, Capabilities, BorrowValue) &Account) {
        // Borrow FlowToken vault for fees
        let flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("Cannot borrow FlowToken vault for fees")

        let feesVault <- flowVault.withdraw(amount: feeAmount) as! @FlowToken.Vault

        // Borrow the scheduler manager from emulator/testnet contract
        let schedulerManager = getAccount(0xf8d6e0586b0a20c7).capabilities
            .borrow<&{FlowTransactionScheduler.SchedulerManager}>(
                /public/flowTransactionScheduler
            ) ?? panic("Cannot borrow FlowTransactionScheduler manager")

        ScheduledManager.scheduleCheck(
            signer: signer,
            schedulerManager: schedulerManager,
            targetTimestamp: targetTimestamp,
            priority: FlowTransactionScheduler.Priority.medium,
            intentIDs: intentIDs,
            feesVault: <- feesVault
        )

        log("Position check scheduled for timestamp: ".concat(targetTimestamp.toString()))
    }
}
