/// getPendingExecution.cdc
/// Returns all intents in BidSelected status that are awaiting execution by the winning solver.

import IntentMarketplaceV0_1 from "IntentMarketplaceV0_1"
import BidManagerV0_1 from "BidManagerV0_1"

access(all) struct PendingExecutionView {
    access(all) let intentID: UInt64
    access(all) let owner: Address
    access(all) let principalAmount: UFix64
    access(all) let targetAPY: UFix64
    access(all) let winningBidID: UInt64
    access(all) let winningSOlverAddress: Address
    access(all) let winningSOlverEVMAddress: String
    access(all) let offeredAPY: UFix64
    access(all) let score: UFix64
    access(all) let expiryBlock: UInt64

    init(
        intentID: UInt64, owner: Address, principalAmount: UFix64,
        targetAPY: UFix64, winningBidID: UInt64,
        winningSOlverAddress: Address, winningSOlverEVMAddress: String,
        offeredAPY: UFix64, score: UFix64, expiryBlock: UInt64
    ) {
        self.intentID = intentID; self.owner = owner
        self.principalAmount = principalAmount; self.targetAPY = targetAPY
        self.winningBidID = winningBidID
        self.winningSOlverAddress = winningSOlverAddress
        self.winningSOlverEVMAddress = winningSOlverEVMAddress
        self.offeredAPY = offeredAPY; self.score = score
        self.expiryBlock = expiryBlock
    }
}

access(all) fun main(): [PendingExecutionView] {
    var result: [PendingExecutionView] = []
    var i: UInt64 = 0

    while i < IntentMarketplaceV0_1.totalIntents {
        if let intent = IntentMarketplaceV0_1.getIntent(id: i) {
            if intent.status == IntentMarketplaceV0_1.IntentStatus.BidSelected {
                if let winningBidID = intent.winningBidID {
                    if let bid = BidManagerV0_1.getBid(bidID: winningBidID) {
                        result.append(PendingExecutionView(
                            intentID: i,
                            owner: intent.owner,
                            principalAmount: intent.principalAmount,
                            targetAPY: intent.targetAPY,
                            winningBidID: winningBidID,
                            winningSOlverAddress: bid.solverAddress,
                            winningSOlverEVMAddress: bid.solverEVMAddress,
                            offeredAPY: bid.offeredAPY,
                            score: bid.score,
                            expiryBlock: intent.expiryBlock
                        ))
                    }
                }
            }
        }
        i = i + 1
    }

    return result
}
