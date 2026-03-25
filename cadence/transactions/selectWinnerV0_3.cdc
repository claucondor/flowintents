/// selectWinnerV0_3.cdc
/// Intent owner selects the winning bid via BidManagerV0_3 (with gas-weighted scoring).

import BidManagerV0_3 from "BidManagerV0_3"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_3.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("V0_3 Winner selected for intent ".concat(intentID.toString()))
    }
}
