/// selectWinnerV0_3.cdc
/// Intent owner selects the winning bid via BidManagerV0_2 (with gas-weighted scoring).

import BidManagerV0_2 from "BidManagerV0_2"

transaction(intentID: UInt64) {
    let callerAddress: Address

    prepare(signer: auth(Storage) &Account) {
        self.callerAddress = signer.address
    }

    execute {
        BidManagerV0_2.selectWinner(intentID: intentID, callerAddress: self.callerAddress)
        log("V0_3 Winner selected for intent ".concat(intentID.toString()))
    }
}
