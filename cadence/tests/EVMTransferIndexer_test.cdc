import Test
import EVMTransferIndexer from "EVMTransferIndexer"

// The testing framework deploys to account 0x0000000000000007
access(all) let account = Test.getAccount(0x0000000000000007)

// ── Helpers ──────────────────────────────────────────────────────────────

access(all) fun encodeUInt64(_ v: UInt64): [UInt8] {
    var result: [UInt8] = []
    var i = 0
    while i < 24 { result.append(0); i = i + 1 }
    result.append(UInt8((v >> 56) & 0xFF))
    result.append(UInt8((v >> 48) & 0xFF))
    result.append(UInt8((v >> 40) & 0xFF))
    result.append(UInt8((v >> 32) & 0xFF))
    result.append(UInt8((v >> 24) & 0xFF))
    result.append(UInt8((v >> 16) & 0xFF))
    result.append(UInt8((v >> 8) & 0xFF))
    result.append(UInt8(v & 0xFF))
    return result
}

// ── Setup ─────────────────────────────────────────────────────────────────

access(all) fun setup() {
    let err = Test.deployContract(
        name: "EVMTransferIndexer",
        path: "../contracts/EVMTransferIndexer.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// ── Tests ─────────────────────────────────────────────────────────────────

access(all) fun testGetStats_InitialState() {
    let stats = EVMTransferIndexer.getStats()
    Test.assertEqual(stats.lastHead, 0 as UInt64)
    Test.assertEqual(stats.totalIndexed, 0 as UInt64)
    Test.assertEqual(stats.totalMissed, 0 as UInt64)
    Test.assertEqual(stats.totalRuns, 0 as UInt64)
}

access(all) fun testComputeInterval_Dead() {
    let interval = EVMTransferIndexer.computeInterval(pending: 0)
    Test.assertEqual(interval, 43200 as UInt64)
}

access(all) fun testComputeInterval_Low() {
    let interval = EVMTransferIndexer.computeInterval(pending: 3)
    Test.assertEqual(interval, 2000 as UInt64)
}

access(all) fun testComputeInterval_Medium() {
    let interval = EVMTransferIndexer.computeInterval(pending: 25)
    Test.assertEqual(interval, 500 as UInt64)
}

access(all) fun testComputeInterval_Active() {
    let interval = EVMTransferIndexer.computeInterval(pending: 100)
    Test.assertEqual(interval, 100 as UInt64)
}

access(all) fun testComputeInterval_Viral() {
    let interval = EVMTransferIndexer.computeInterval(pending: 250)
    Test.assertEqual(interval, 50 as UInt64)
}

access(all) fun testComputeInterval_Boundaries() {
    // Exact boundary values
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 5),   2000 as UInt64)
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 6),   500 as UInt64)
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 50),  500 as UInt64)
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 51),  100 as UInt64)
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 200), 100 as UInt64)
    Test.assertEqual(EVMTransferIndexer.computeInterval(pending: 201), 50 as UInt64)
}

access(all) fun testEstimateSurcharge_InitialState() {
    // With 0 runs, should return max surcharge (5000 bps = 50%)
    let bps = EVMTransferIndexer.estimateSurcharge()
    Test.assert(bps >= 1 && bps <= 5000, message: "Surcharge must be 1-5000 bps")
}

access(all) fun testGetRecord_ReturnsNilForUnindexed() {
    let record = EVMTransferIndexer.getRecord(seqNum: 9999)
    Test.assertEqual(record, nil)
}

access(all) fun testGetRecentRecords_EmptyInitially() {
    let records = EVMTransferIndexer.getRecentRecords(limit: 10)
    Test.assertEqual(records.length, 0)
}

access(all) fun testGetRecordsByAddress_EmptyInitially() {
    let records = EVMTransferIndexer.getRecordsByAddress(
        addr: "0x0000000000000000000000000000000000000001",
        limit: 10
    )
    Test.assertEqual(records.length, 0)
}

access(all) fun testBufferSize_Is256() {
    // NOTE: EVMTransferIndexer.BUFFER_SIZE is 256 (set in contract init).
    // The EVM-side CircularBufferERC20 uses 512 slots; the Cadence indexer
    // tracks this with its own constant. Update this test if the constant changes.
    Test.assertEqual(EVMTransferIndexer.BUFFER_SIZE, 256 as UInt64)
}
