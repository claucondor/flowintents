/// relayEVMBid.cdc
/// Reads a bid from EVMBidRelay.sol (EVM) and submits it to BidManagerV0_3 (Cadence).
/// This allows EVM-only solvers to participate without a Cadence account.
/// The relayer (any Cadence account) calls this transaction on behalf of the EVM solver.
///
/// Supports both yield bids (offeredAPY > 0, offeredAmountOut = 0.0) and
/// swap bids (offeredAmountOut > 0, offeredAPY = 0.0).
///
/// NOTE: SolverRegistryV0_1.getSolverByEVM(evmAddress: String): SolverInfo?
/// is used to look up the Cadence address for the EVM solver.
/// The EVM solver MUST have registered once in SolverRegistryV0_1.
///
/// Parameters re-stated explicitly to avoid full ABI decoding of encodedBatch in Cadence.
/// The relayer is responsible for reading the EVMBidRelay contract off-chain and passing
/// the correct values here.

import EVM from "EVM"
import BidManagerV0_3 from "BidManagerV0_3"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

transaction(
    intentId:          UInt64,
    solverEVMAddress:  String,      // EVM address of the solver (must be registered)
    offeredAPY:        UFix64,      // APY in UFix64 (e.g. 5.0 = 5%); 0.0 for swap bids
    offeredAmountOut:  UFix64,      // Offered output amount; 0.0 for yield bids
    maxGasBid:         UFix64,      // Max gas bid in FLOW (e.g. 0.1)
    strategy:          String,      // JSON strategy description
    encodedBatch:      [UInt8]      // ABI-encoded StrategyStep[] for FlowIntentsComposerV4
) {
    prepare(signer: auth(Storage) &Account) {
        // Relayer just needs to exist and pay gas.
    }

    execute {
        // Validate that exactly one of offeredAPY / offeredAmountOut is set
        assert(
            offeredAPY > 0.0 || offeredAmountOut > 0.0,
            message: "relayEVMBid: must provide offeredAPY (yield) or offeredAmountOut (swap)"
        )

        // Look up the Cadence address registered for this EVM solver.
        let solverInfo = SolverRegistryV0_1.getSolverByEVM(evmAddress: solverEVMAddress)
            ?? panic(
                "EVM solver not registered in SolverRegistryV0_1 — "
                .concat("solver must call registerSolverWithAddress once")
            )

        let solverCadenceAddr = solverInfo.cadenceAddress

        // Build optional APY / amountOut values for the bid manager
        let apyOpt:       UFix64? = offeredAPY > 0.0       ? offeredAPY       : nil
        let amountOutOpt: UFix64? = offeredAmountOut > 0.0 ? offeredAmountOut : nil

        // Submit the bid on behalf of the EVM solver via BidManagerV0_3
        BidManagerV0_3.submitBid(
            intentID:         intentId,
            solverAddress:    solverCadenceAddr,
            offeredAPY:       apyOpt,
            offeredAmountOut: amountOutOpt,
            estimatedFeeBPS:  nil,
            targetChain:      nil,
            maxGasBid:        maxGasBid,
            strategy:         strategy,
            encodedBatch:     encodedBatch
        )

        log(
            "EVM bid relayed for intent "
                .concat(intentId.toString())
                .concat(" from EVM solver ")
                .concat(solverEVMAddress)
        )
    }
}
