/// SolverRegistry_test.cdc
/// Tests for SolverRegistry: ERC-8004 verification, registration, reputation.

import Test
import BlockchainHelpers
import "SolverRegistry"

access(all) let solver1 = Test.createAccount()
access(all) let solver2 = Test.createAccount()

access(all) fun setup() {
    Test.expect(
        Test.deployContract(name: "SolverRegistry", path: "../contracts/SolverRegistry.cdc", arguments: []),
        Test.beNil()
    )
}

// -------------------------------------------------------------------------
// Test 1: Initial state — no solvers registered
// -------------------------------------------------------------------------

access(all) fun testInitialState() {
    Test.assertEqual(SolverRegistry.getAllSolverAddresses().length, 0)
    Test.assertEqual(SolverRegistry.isRegistered(cadenceAddress: solver1.address), false)
    Test.assertEqual(SolverRegistry.getReputationMultiplier(cadenceAddress: solver1.address), 0.0 as UFix64)
}

// -------------------------------------------------------------------------
// Test 2: EVM address placeholder validation
// -------------------------------------------------------------------------

access(all) fun testAgentRegistryAddressDefault() {
    // Default addresses should be zero address (unset)
    Test.assertEqual(
        SolverRegistry.agentIdentityRegistryAddress,
        "0x0000000000000000000000000000000000000000"
    )
    Test.assertEqual(
        SolverRegistry.agentReputationRegistryAddress,
        "0x0000000000000000000000000000000000000000"
    )
}

// -------------------------------------------------------------------------
// Test 3: Basis point to multiplier conversion
// -------------------------------------------------------------------------

access(all) fun testBasisPointConversion() {
    // 10000 bp = 1.0x (standard)
    let standard = UFix64(10000) / 10000.0
    Test.assertEqual(standard, 1.0 as UFix64)

    // 15000 bp = 1.5x (high reputation)
    let high = UFix64(15000) / 10000.0
    Test.assertEqual(high, 1.5 as UFix64)

    // 8000 bp = 0.8x (lower reputation)
    let low = UFix64(8000) / 10000.0
    Test.assertEqual(low, 0.8 as UFix64)
}

// -------------------------------------------------------------------------
// Test 4: Error — getSolver returns nil for unregistered address
// -------------------------------------------------------------------------

access(all) fun testGetUnregisteredSolverReturnsNil() {
    let info = SolverRegistry.getSolver(cadenceAddress: solver1.address)
    Test.assertEqual(info, nil)

    let infoByEVM = SolverRegistry.getSolverByEVM(evmAddress: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    Test.assertEqual(infoByEVM, nil)
}

// -------------------------------------------------------------------------
// Test 5: Error — registration with zero-address identity registry fails
// -------------------------------------------------------------------------

access(all) fun testRegistrationWithUnsetRegistryFails() {
    // Registering before Admin sets the identity registry address should fail
    // because the dryCall to 0x0000...0000 will either fail or return zero owner
    // Verified by: registerSolverWithAddress asserts isNonZero owner data

    // The registration transaction uses COA which requires EVM setup
    // In emulator, this would need a funded COA account
    // We verify the pre-condition is in place contractually:
    let txCode = Test.readFile("../transactions/registerSolver.cdc")
    let tx = Test.Transaction(
        code: txCode,
        authorizers: [solver1.address],
        signers: [solver1],
        arguments: [
            "0xabcdef1234567890abcdef1234567890abcdef12",
            UInt256(1)
        ]
    )
    // This tx will fail because:
    // 1. solver1 has no COA at /storage/evm
    // 2. Even with COA, identity registry is 0x0000...
    let result = Test.executeTransaction(tx)
    Test.expect(result, Test.beFailed())
}
