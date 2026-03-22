import IntentMarketplaceV0_2 from "IntentMarketplaceV0_2"

access(all) fun main(intentID: UInt64): {String: AnyStruct}? {
    let intent = IntentMarketplaceV0_2.getIntent(id: intentID)
    if intent == nil {
        return nil
    }
    let i = intent!
    return {
        "id": i.id,
        "owner": i.intentOwner,
        "principalAmount": i.principalAmount,
        "targetAPY": i.targetAPY,
        "durationDays": i.durationDays,
        "expiryBlock": i.expiryBlock,
        "status": i.status.rawValue,
        "principalSide": i.principalSide.rawValue,
        "intentType": i.intentType.rawValue,
        "createdAt": i.createdAt
    }
}
