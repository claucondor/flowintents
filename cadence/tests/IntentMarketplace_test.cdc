/// IntentMarketplace_test.cdc
/// Tests for IntentMarketplace contract.
/// Covers: happy path, cancel, expiry, vault balance assertions.

import Test
import BlockchainHelpers
import "IntentMarketplace"
import "FungibleToken"
import "FlowToken"

access(all) let account = Test.getAccount(0x0000000000000007)
access(all) let alice    = Test.createAccount()
access(all) let bob      = Test.createAccount()

// -------------------------------------------------------------------------
// Setup
// -------------------------------------------------------------------------

access(all) fun setup() {
    // Deploy IntentMarketplace
    let err = Test.deployContract(
        name: "IntentMarketplace",
        path: "../contracts/IntentMarketplace.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// -------------------------------------------------------------------------
// Helper: fund an account with FlowToken
// -------------------------------------------------------------------------

access(all) fun fundAccount(_ acct: Test.TestAccount, amount: UFix64) {
    let code = Test.readFile("../transactions/createIntent.cdc")
    // Use emulator faucet helper
    let txResult = BlockchainHelpers.mintFlow(to: acct, amount: amount)
    Test.expect(txResult, Test.beSucceeded())
}

// -------------------------------------------------------------------------
// Test 1: Happy path — create intent, verify vault balance
// -------------------------------------------------------------------------

access(all) fun testCreateIntent() {
    let mintResult = BlockchainHelpers.mintFlow(to: alice, amount: 100.0)
    Test.expect(mintResult, Test.beSucceeded())

    // Record alice's balance before
    let balanceBefore = BlockchainHelpers.getFlowBalance(alice)

    let txCode = Test.readFile("../transactions/createIntent.cdc")
    let tx = Test.Transaction(
        code: txCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [
            100.0,   // amount
            5.0,     // targetAPY (5%)
            30,      // durationDays
            UInt64(getCurrentBlock().height + 1000)  // expiryBlock
        ]
    )
    let txResult = Test.executeTransaction(tx)
    Test.expect(txResult, Test.beSucceeded())

    // Verify intent was created
    let scriptCode = Test.readFile("../scripts/getIntent.cdc")
    let scriptResult = Test.executeScript(scriptCode, [UInt64(0)])
    Test.expect(scriptResult, Test.beSucceeded())

    let intentView = scriptResult.returnValue! as! {String: AnyStruct}
    Test.assertEqual(intentView["id"] as! UInt64, UInt64(0))
    Test.assertEqual(intentView["owner"] as! Address, alice.address)
    Test.assertEqual(intentView["status"] as! UInt8, UInt8(0)) // Open

    // Vault balance assertions — principal locked inside intent
    let vaultBalance = intentView["vaultBalance"] as! UFix64
    Test.assertEqual(vaultBalance, 100.0)

    // Alice's flow balance decreased
    let balanceAfter = BlockchainHelpers.getFlowBalance(alice)
    Test.assert(balanceAfter < balanceBefore, message: "Alice balance should decrease after creating intent")
}

// -------------------------------------------------------------------------
// Test 2: Happy path — cancel intent, funds returned
// -------------------------------------------------------------------------

access(all) fun testCancelIntent() {
    let mintResult = BlockchainHelpers.mintFlow(to: alice, amount: 50.0)
    Test.expect(mintResult, Test.beSucceeded())

    // Create intent
    let createCode = Test.readFile("../transactions/createIntent.cdc")
    let createTx = Test.Transaction(
        code: createCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [
            50.0,
            3.0,
            7,
            UInt64(getCurrentBlock().height + 500)
        ]
    )
    let createResult = Test.executeTransaction(createTx)
    Test.expect(createResult, Test.beSucceeded())

    let intentID = IntentMarketplace.totalIntents - 1
    let balanceBeforeCancel = BlockchainHelpers.getFlowBalance(alice)

    // Cancel intent
    let cancelCode = Test.readFile("../transactions/cancelIntent.cdc")
    let cancelTx = Test.Transaction(
        code: cancelCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [intentID]
    )
    let cancelResult = Test.executeTransaction(cancelTx)
    Test.expect(cancelResult, Test.beSucceeded())

    // Vault balance assertions — funds returned to alice
    let balanceAfterCancel = BlockchainHelpers.getFlowBalance(alice)
    Test.assert(balanceAfterCancel > balanceBeforeCancel, message: "Funds should be returned on cancel")

    // Verify status is Cancelled
    let scriptCode = Test.readFile("../scripts/getIntent.cdc")
    let scriptResult = Test.executeScript(scriptCode, [intentID])
    Test.expect(scriptResult, Test.beSucceeded())
    let intentView = scriptResult.returnValue! as! {String: AnyStruct}
    Test.assertEqual(intentView["status"] as! UInt8, UInt8(4)) // Cancelled
}

// -------------------------------------------------------------------------
// Test 3: Error — non-owner cannot cancel
// -------------------------------------------------------------------------

access(all) fun testCancelByNonOwnerFails() {
    let mintAlice = BlockchainHelpers.mintFlow(to: alice, amount: 50.0)
    let mintBob   = BlockchainHelpers.mintFlow(to: bob, amount: 10.0)
    Test.expect(mintAlice, Test.beSucceeded())
    Test.expect(mintBob,   Test.beSucceeded())

    let createCode = Test.readFile("../transactions/createIntent.cdc")
    let createTx = Test.Transaction(
        code: createCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [
            50.0, 4.0, 14,
            UInt64(getCurrentBlock().height + 300)
        ]
    )
    let createResult = Test.executeTransaction(createTx)
    Test.expect(createResult, Test.beSucceeded())

    let intentID = IntentMarketplace.totalIntents - 1

    // Bob tries to cancel alice's intent
    let cancelCode = Test.readFile("../transactions/cancelIntent.cdc")
    let cancelTx = Test.Transaction(
        code: cancelCode,
        authorizers: [bob.address],
        signers: [bob],
        arguments: [intentID]
    )
    let cancelResult = Test.executeTransaction(cancelTx)
    Test.expect(cancelResult, Test.beFailed())
    Test.assert(cancelResult.error!.message.contains("Only the intent owner can cancel"),
        message: "Expected ownership error")
}

// -------------------------------------------------------------------------
// Test 4: Error — create intent with zero amount fails
// -------------------------------------------------------------------------

access(all) fun testCreateIntentZeroAmountFails() {
    let mintResult = BlockchainHelpers.mintFlow(to: alice, amount: 10.0)
    Test.expect(mintResult, Test.beSucceeded())

    let createCode = Test.readFile("../transactions/createIntent.cdc")
    let createTx = Test.Transaction(
        code: createCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [
            0.0,  // zero amount — should fail
            5.0, 30,
            UInt64(getCurrentBlock().height + 500)
        ]
    )
    let result = Test.executeTransaction(createTx)
    Test.expect(result, Test.beFailed())
    Test.assert(result.error!.message.contains("Principal vault cannot be empty"),
        message: "Expected empty vault error")
}

// -------------------------------------------------------------------------
// Test 5: Intent expiry — expireIntent works after block passes
// -------------------------------------------------------------------------

access(all) fun testExpireIntent() {
    let mintResult = BlockchainHelpers.mintFlow(to: alice, amount: 25.0)
    Test.expect(mintResult, Test.beSucceeded())

    let currentBlock = getCurrentBlock().height
    let createCode = Test.readFile("../transactions/createIntent.cdc")
    let createTx = Test.Transaction(
        code: createCode,
        authorizers: [alice.address],
        signers: [alice],
        arguments: [
            25.0, 6.0, 7,
            UInt64(currentBlock + 1)  // expires very soon
        ]
    )
    let createResult = Test.executeTransaction(createTx)
    Test.expect(createResult, Test.beSucceeded())

    let intentID = IntentMarketplace.totalIntents - 1

    // Advance the blockchain past expiry block
    Test.moveToNextBlock()
    Test.moveToNextBlock()

    let balanceBeforeExpiry = BlockchainHelpers.getFlowBalance(alice)

    // Marketplace borrow and expire
    let marketplace = getAccount(IntentMarketplace.account.address).storage
        .borrow<&IntentMarketplace.Marketplace>(from: IntentMarketplace.MarketplaceStoragePath)!
    let receiver = getAccount(alice.address).storage
        .borrow<&{FungibleToken.Receiver}>(from: /storage/flowTokenVault)!
    marketplace.expireIntent(id: intentID, receiver: receiver)

    // Status should be Expired
    let scriptCode = Test.readFile("../scripts/getIntent.cdc")
    let scriptResult = Test.executeScript(scriptCode, [intentID])
    let intentView = scriptResult.returnValue! as! {String: AnyStruct}
    Test.assertEqual(intentView["status"] as! UInt8, UInt8(5)) // Expired

    // Vault balance — alice got funds back
    let vaultBalance = intentView["vaultBalance"] as! UFix64
    Test.assertEqual(vaultBalance, 0.0)
}
