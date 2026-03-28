/// run_indexer.cdc
/// Standalone manual indexer transaction.
/// Reads pending ERC20 transfers from CircularBufferERC20 and stores them
/// in EVMTransferIndexer. Use this for manual testing without the scheduler.
///
/// Steps:
///   1. Borrows COA from signer storage
///   2. Calls pendingSince(lastHead) on CircularBufferERC20
///   3. Reads all pending records with getRecord(seq)
///   4. Saves records to indexer contract storage
///   5. Logs gas used per step

import EVM from "EVM"
import EVMTransferIndexer from "EVMTransferIndexer"

transaction {
    prepare(signer: auth(Storage) &Account) {
        let startBlock = getCurrentBlock().height
        log("=== EVMTransferIndexer Manual Run ===")
        log("Block: ".concat(startBlock.toString()))

        // Step 1: Borrow COA
        let coa = signer.storage.borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("No COA found at /storage/evm. Run 'setup_coa.cdc' first.")

        log("COA address: ".concat(coa.address().toString()))

        // Step 2: Check current state
        let statsBefore = EVMTransferIndexer.getStats()
        log("Last head before: ".concat(statsBefore.lastHead.toString()))
        log("Total indexed before: ".concat(statsBefore.totalIndexed.toString()))

        // Step 3: Run the indexer (makes EVM calls internally)
        let interval = EVMTransferIndexer.runIndexer(coa: coa)

        // Step 4: Report results
        let statsAfter = EVMTransferIndexer.getStats()
        log("Last head after: ".concat(statsAfter.lastHead.toString()))
        log("Total indexed after: ".concat(statsAfter.totalIndexed.toString()))
        log("Total missed: ".concat(statsAfter.totalMissed.toString()))
        log("Records this run: ".concat((statsAfter.totalIndexed - statsBefore.totalIndexed).toString()))
        log("Pending last run: ".concat(statsAfter.lastRunPending.toString()))
        log("Next interval (blocks): ".concat(interval.toString()))
        log("Surcharge estimate: ".concat(EVMTransferIndexer.estimateSurcharge().toString()).concat(" bps"))
    }
}
