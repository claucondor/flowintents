/// getSolverScore.cdc
/// Returns the score a solver would receive for a given APY offer,
/// based on their current reputation multiplier from SolverRegistry.

import SolverRegistry from "SolverRegistry"

access(all) struct SolverScoreView {
    access(all) let cadenceAddress: Address
    access(all) let evmAddress: String
    access(all) let reputationMultiplier: UFix64
    access(all) let projectedScore: UFix64
    access(all) let isRegistered: Bool

    init(
        cadenceAddress: Address, evmAddress: String,
        reputationMultiplier: UFix64, projectedScore: UFix64, isRegistered: Bool
    ) {
        self.cadenceAddress = cadenceAddress
        self.evmAddress = evmAddress
        self.reputationMultiplier = reputationMultiplier
        self.projectedScore = projectedScore
        self.isRegistered = isRegistered
    }
}

access(all) fun main(solverAddress: Address, offeredAPY: UFix64): SolverScoreView {
    if let info = SolverRegistry.getSolver(cadenceAddress: solverAddress) {
        let score = offeredAPY * info.reputationMultiplier
        return SolverScoreView(
            cadenceAddress: solverAddress,
            evmAddress: info.evmAddress,
            reputationMultiplier: info.reputationMultiplier,
            projectedScore: score,
            isRegistered: true
        )
    }
    return SolverScoreView(
        cadenceAddress: solverAddress,
        evmAddress: "",
        reputationMultiplier: 0.0,
        projectedScore: 0.0,
        isRegistered: false
    )
}
