/// relayEVMBid.cdc
/// Reads a bid from EVMBidRelay.sol (EVM) and submits it to BidManagerV0_2 (Cadence).
/// This allows EVM-only solvers to participate without a Cadence account.
/// The relayer (any Cadence account) calls this transaction on behalf of the EVM solver.
///
/// NOTE: SolverRegistryV0_1 does not expose a getCadenceAddressByEVM() function.
/// Instead, it exposes getSolverByEVM(evmAddress: String): SolverInfo? which returns
/// the full SolverInfo including the cadenceAddress field.
/// The EVM solver MUST have registered once in SolverRegistryV0_1 (via registerSolverWithAddress
/// called from a Cadence account that controls a COA, or by a relayer on their behalf).
///
/// Parameters re-stated explicitly to avoid full ABI decoding of encodedBatch in Cadence.
/// The relayer is responsible for reading the EVMBidRelay contract off-chain and passing
/// the correct values here.

import EVM from "EVM"
import BidManagerV0_2 from "BidManagerV0_2"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

transaction(
    intentId: UInt64,
    solverEVMAddress: String,   // EVM address of the solver (must be registered in SolverRegistryV0_1)
    offeredAPY: UFix64,         // APY in UFix64 (e.g. 5.0 = 5%)
    maxGasBid: UFix64,          // max gas bid in FLOW (e.g. 0.1)
    strategy: String,           // JSON strategy description
    encodedBatch: [UInt8]       // ABI-encoded StrategyStep[] for FlowIntentsComposerV2
) {
    prepare(signer: auth(Storage) &Account) {
        // Relayer just needs to exist and pay gas.
        // Solver is identified by their registered EVM address.
    }

    execute {
        // Look up the Cadence address registered for this EVM solver.
        // SolverRegistryV0_1.getSolverByEVM returns SolverInfo? which includes cadenceAddress.
        let solverInfo = SolverRegistryV0_1.getSolverByEVM(evmAddress: solverEVMAddress)
            ?? panic("EVM solver not registered in SolverRegistryV0_1 — solver must call registerSolverWithAddress once (can be done by a relayer with COA)")

        let solverCadenceAddr = solverInfo.cadenceAddress

        // Submit the bid on behalf of the EVM solver.
        BidManagerV0_2.submitBid(
            intentID: intentId,
            solverAddress: solverCadenceAddr,
            offeredAPY: offeredAPY,
            offeredAmountOut: nil,
            estimatedFeeBPS: nil,
            targetChain: nil,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch
        )

        log("EVM bid relayed for intent ".concat(intentId.toString()).concat(" from EVM solver ").concat(solverEVMAddress))
    }
}
