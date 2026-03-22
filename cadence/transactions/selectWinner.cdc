/// selectWinner.cdc
/// Intent owner selects the winning bid (highest score; earliest submission on tie).

import BidManagerV0_1 from "BidManagerV0_1"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_1.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("Winner selected for intent ".concat(intentID.toString()))
    }
}
