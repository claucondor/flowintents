/// selectWinner.cdc
/// Intent owner selects the winning bid (highest score; earliest submission on tie).

import BidManager from "BidManager"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManager.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("Winner selected for intent ".concat(intentID.toString()))
    }
}
