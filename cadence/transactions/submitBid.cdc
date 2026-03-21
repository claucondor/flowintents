/// submitBid.cdc
/// Submits a solver bid for an open intent.
/// Signer must be a registered solver in SolverRegistry.

import BidManager from "BidManager"

transaction(
    intentID: UInt64,
    offeredAPY: UFix64,
    strategy: String,
    encodedBatch: [UInt8]
) {
    let solverAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.solverAddress = signer.address
    }

    execute {
        let bidID = BidManager.submitBid(
            intentID: intentID,
            solverAddress: self.solverAddress,
            offeredAPY: offeredAPY,
            strategy: strategy,
            encodedBatch: encodedBatch
        )
        log("Bid ".concat(bidID.toString()).concat(" submitted for intent ").concat(intentID.toString()))
    }
}
