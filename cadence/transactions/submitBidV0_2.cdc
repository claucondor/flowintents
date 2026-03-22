/// submitBidV0_2.cdc
/// Submits a solver bid for an open intent via BidManagerV0_2.
/// Includes gas escrow field: maxGasBid (the max gas escrow the solver requests from user).
/// Signer must be a registered solver in SolverRegistry.

import BidManagerV0_2 from "BidManagerV0_2"

transaction(
    intentID: UInt64,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?,
    targetChain: String?,
    maxGasBid: UFix64,
    strategy: String,
    encodedBatch: [UInt8]
) {
    let solverAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.solverAddress = signer.address
    }

    execute {
        let bidID = BidManagerV0_2.submitBid(
            intentID: intentID,
            solverAddress: self.solverAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            estimatedFeeBPS: estimatedFeeBPS,
            targetChain: targetChain,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch
        )
        log("V0_2 Bid ".concat(bidID.toString()).concat(" submitted for intent ").concat(intentID.toString()))
    }
}
