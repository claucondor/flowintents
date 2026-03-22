import SolverRegistryV0_2 from "SolverRegistryV0_2"

access(all) fun main(addr: Address): UFix64 {
    return SolverRegistryV0_2.getReputationMultiplier(cadenceAddress: addr)
}
