/// getActiveBids.cdc
/// Returns all bids for a given intentID with their scores.

import BidManager from "BidManager"

access(all) struct BidView {
    access(all) let bidID: UInt64
    access(all) let intentID: UInt64
    access(all) let solverAddress: Address
    access(all) let solverEVMAddress: String
    access(all) let offeredAPY: UFix64
    access(all) let strategy: String
    access(all) let submittedAt: UFix64
    access(all) let score: UFix64

    init(
        bidID: UInt64, intentID: UInt64, solverAddress: Address,
        solverEVMAddress: String, offeredAPY: UFix64, strategy: String,
        submittedAt: UFix64, score: UFix64
    ) {
        self.bidID = bidID; self.intentID = intentID; self.solverAddress = solverAddress
        self.solverEVMAddress = solverEVMAddress; self.offeredAPY = offeredAPY
        self.strategy = strategy; self.submittedAt = submittedAt; self.score = score
    }
}

access(all) fun main(intentID: UInt64): [BidView] {
    let bidIDs = BidManager.getBidsForIntent(intentID: intentID)
    var result: [BidView] = []

    for bidID in bidIDs {
        if let bid = BidManager.getBid(bidID: bidID) {
            result.append(BidView(
                bidID: bid.id,
                intentID: bid.intentID,
                solverAddress: bid.solverAddress,
                solverEVMAddress: bid.solverEVMAddress,
                offeredAPY: bid.offeredAPY,
                strategy: bid.strategy,
                submittedAt: bid.submittedAt,
                score: bid.score
            ))
        }
    }

    return result
}
