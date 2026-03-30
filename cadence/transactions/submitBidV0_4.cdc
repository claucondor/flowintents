/// submitBidV0_4.cdc
/// Submit a solver bid for an open V0_4 intent.
/// Solver must be registered in SolverRegistryV0_1.

import BidManagerV0_4 from "BidManagerV0_4"

transaction(
    intentID: UInt64,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    maxGasBid: UFix64,
    strategy: String,
    encodedBatch: [UInt8]
) {
    let solverAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.solverAddress = signer.address
    }

    execute {
        let bidID = BidManagerV0_4.submitBid(
            intentID: intentID,
            solverAddress: self.solverAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch
        )
        log("V0_4 Bid ".concat(bidID.toString()).concat(" submitted for intent ").concat(intentID.toString()))
    }
}
