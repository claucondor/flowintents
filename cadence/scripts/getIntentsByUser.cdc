/// getIntentsByUser.cdc
/// Returns all intent IDs and summary info for a given user address.

import IntentMarketplace from "IntentMarketplace"

access(all) struct IntentSummary {
    access(all) let id: UInt64
    access(all) let principalAmount: UFix64
    access(all) let targetAPY: UFix64
    access(all) let status: UInt8
    access(all) let expiryBlock: UInt64
    access(all) let winningBidID: UInt64?

    init(
        id: UInt64, principalAmount: UFix64, targetAPY: UFix64,
        status: UInt8, expiryBlock: UInt64, winningBidID: UInt64?
    ) {
        self.id = id; self.principalAmount = principalAmount
        self.targetAPY = targetAPY; self.status = status
        self.expiryBlock = expiryBlock; self.winningBidID = winningBidID
    }
}

access(all) fun main(userAddress: Address): [IntentSummary] {
    let intentIDs = IntentMarketplace.getIntentsByUser(owner: userAddress)
    var result: [IntentSummary] = []

    for id in intentIDs {
        if let intent = IntentMarketplace.getIntent(id: id) {
            result.append(IntentSummary(
                id: intent.id,
                principalAmount: intent.principalAmount,
                targetAPY: intent.targetAPY,
                status: intent.status.rawValue,
                expiryBlock: intent.expiryBlock,
                winningBidID: intent.winningBidID
            ))
        }
    }

    return result
}
