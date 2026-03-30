/// selectWinnerV0_4.cdc
/// Intent owner selects the winning bid via BidManagerV0_4.

import BidManagerV0_4 from "BidManagerV0_4"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_4.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("V0_4 Winner selected for intent ".concat(intentID.toString()))
    }
}
