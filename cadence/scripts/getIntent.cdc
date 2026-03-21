/// getIntent.cdc
/// Returns all fields of an intent by ID.

import IntentMarketplace from "IntentMarketplace"

access(all) struct IntentView {
    access(all) let id: UInt64
    access(all) let owner: Address
    access(all) let tokenType: String
    access(all) let principalAmount: UFix64
    access(all) let vaultBalance: UFix64
    access(all) let targetAPY: UFix64
    access(all) let durationDays: UInt64
    access(all) let expiryBlock: UInt64
    access(all) let status: UInt8
    access(all) let winningBidID: UInt64?
    access(all) let createdAt: UFix64

    init(
        id: UInt64, owner: Address, tokenType: String,
        principalAmount: UFix64, vaultBalance: UFix64,
        targetAPY: UFix64, durationDays: UInt64,
        expiryBlock: UInt64, status: UInt8,
        winningBidID: UInt64?, createdAt: UFix64
    ) {
        self.id = id; self.owner = owner; self.tokenType = tokenType
        self.principalAmount = principalAmount; self.vaultBalance = vaultBalance
        self.targetAPY = targetAPY; self.durationDays = durationDays
        self.expiryBlock = expiryBlock; self.status = status
        self.winningBidID = winningBidID; self.createdAt = createdAt
    }
}

access(all) fun main(intentID: UInt64): IntentView? {
    if let intent = IntentMarketplace.getIntent(id: intentID) {
        return IntentView(
            id: intent.id,
            owner: intent.owner,
            tokenType: intent.tokenType.identifier,
            principalAmount: intent.principalAmount,
            vaultBalance: intent.principalVault.balance,
            targetAPY: intent.targetAPY,
            durationDays: intent.durationDays,
            expiryBlock: intent.expiryBlock,
            status: intent.status.rawValue,
            winningBidID: intent.winningBidID,
            createdAt: intent.createdAt
        )
    }
    return nil
}
