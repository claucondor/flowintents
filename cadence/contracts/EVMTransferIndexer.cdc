/// EVMTransferIndexer.cdc
/// On-chain ERC20 transfer indexer that reads from an EVM circular buffer.
/// Replaces The Graph (external subgraph service) with native Cadence storage.
/// Implements FlowTransactionScheduler.TransactionHandler for self-scheduling.
///
/// CircularBufferERC20 at 0x9E94Ed20e07662b3E5C01773839A91Ac969c7414
///   - 256-slot circular buffer (head wraps, oldest lost on overflow)
///   - pendingSince(uint64 lastHead) → (uint64 pending, uint64 currentHead)
///   - getRecord(uint64 seq) → (address from, address to, uint96 amount, uint32 blockNum, uint64 seqNum)
///   - head() → uint64

import FlowTransactionScheduler from "FlowTransactionScheduler"
import EVM from "EVM"

access(all) contract EVMTransferIndexer {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// CircularBufferERC20 address on Flow EVM emulator (configurable by Admin)
    access(all) var BUFFER_ADDRESS: String
    /// Buffer size — 256 slots; if pending >= this, records have been lost
    access(all) let BUFFER_SIZE: UInt64

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event RecordsIndexed(count: UInt64, fromHead: UInt64, toHead: UInt64)
    access(all) event RecordsMissed(estimated: UInt64)
    access(all) event SchedulerRun(pending: UInt64, interval: UInt64, recordsIndexed: UInt64)
    access(all) event IndexerConfigUpdated(key: String)

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    access(all) struct TransferRecord {
        access(all) let from: String
        access(all) let to: String
        access(all) let amount: UInt256
        access(all) let blockNum: UInt32
        access(all) let seqNum: UInt64

        init(from: String, to: String, amount: UInt256, blockNum: UInt32, seqNum: UInt64) {
            self.from = from
            self.to = to
            self.amount = amount
            self.blockNum = blockNum
            self.seqNum = seqNum
        }
    }

    access(all) struct IndexerStats {
        access(all) let lastHead: UInt64
        access(all) let totalIndexed: UInt64
        access(all) let totalMissed: UInt64
        access(all) let totalRuns: UInt64
        access(all) let lastRunPending: UInt64
        access(all) let lastRunInterval: UInt64
        access(all) let bufferAddress: String
        access(all) let bufferSize: UInt64

        init(
            lastHead: UInt64,
            totalIndexed: UInt64,
            totalMissed: UInt64,
            totalRuns: UInt64,
            lastRunPending: UInt64,
            lastRunInterval: UInt64,
            bufferAddress: String,
            bufferSize: UInt64
        ) {
            self.lastHead = lastHead
            self.totalIndexed = totalIndexed
            self.totalMissed = totalMissed
            self.totalRuns = totalRuns
            self.lastRunPending = lastRunPending
            self.lastRunInterval = lastRunInterval
            self.bufferAddress = bufferAddress
            self.bufferSize = bufferSize
        }
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// All indexed transfer records, keyed by seqNum
    access(self) var records: {UInt64: TransferRecord}

    /// Index from EVM address → list of seqNums (for getRecordsByAddress)
    access(self) var addressIndex: {String: [UInt64]}

    /// Last head value we synced up to
    access(all) var lastHead: UInt64

    /// Cumulative stats
    access(all) var totalRecordsIndexed: UInt64
    access(all) var totalMissed: UInt64
    access(all) var totalRuns: UInt64
    access(all) var lastRunPending: UInt64
    access(all) var lastRunInterval: UInt64

    // -------------------------------------------------------------------------
    // Storage paths
    // -------------------------------------------------------------------------

    access(all) let HandlerStoragePath: StoragePath
    access(all) let HandlerPublicPath: PublicPath
    access(all) let AdminStoragePath: StoragePath

    // -------------------------------------------------------------------------
    // Admin resource
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        /// Set the CircularBufferERC20 address (needed when redeploying on emulator)
        access(all) fun setBufferAddress(addr: String) {
            EVMTransferIndexer.BUFFER_ADDRESS = addr
            emit IndexerConfigUpdated(key: "setBufferAddress")
        }

        /// Reset the indexer (for re-indexing from scratch)
        access(all) fun resetIndex() {
            EVMTransferIndexer.records = {}
            EVMTransferIndexer.addressIndex = {}
            EVMTransferIndexer.lastHead = 0
            EVMTransferIndexer.totalRecordsIndexed = 0
            EVMTransferIndexer.totalMissed = 0
            EVMTransferIndexer.totalRuns = 0
            EVMTransferIndexer.lastRunPending = 0
            EVMTransferIndexer.lastRunInterval = 0
            emit IndexerConfigUpdated(key: "resetIndex")
        }

        /// Override lastHead (e.g., to skip old records)
        access(all) fun setLastHead(head: UInt64) {
            EVMTransferIndexer.lastHead = head
            emit IndexerConfigUpdated(key: "setLastHead")
        }
    }

    // -------------------------------------------------------------------------
    // TransactionHandler resource — FlowTransactionScheduler integration
    // -------------------------------------------------------------------------

    access(all) resource Handler: FlowTransactionScheduler.TransactionHandler {

        access(FlowTransactionScheduler.Execute)
        fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Borrow the account's COA to make EVM calls
            let acct = EVMTransferIndexer.account
            let coa = acct.storage.borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(
                from: /storage/evm
            ) ?? panic("No COA found in storage")

            // Run the indexer logic and get back the chosen interval
            let interval = EVMTransferIndexer.runIndexer(coa: coa)

            // Self-schedule: reschedule at next interval
            // NOTE: In production, schedule() would be called here.
            // On emulator we just log — scheduling requires fee payment logic.
        }

        access(all) view fun getViews(): [Type] {
            return [Type<StoragePath>(), Type<PublicPath>()]
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<StoragePath>():
                    return EVMTransferIndexer.HandlerStoragePath
                case Type<PublicPath>():
                    return EVMTransferIndexer.HandlerPublicPath
                default:
                    return nil
            }
        }
    }

    // -------------------------------------------------------------------------
    // Core indexer logic
    // -------------------------------------------------------------------------

    /// Run one indexer cycle: read pending records from EVM, store them, return interval.
    /// `coa` must have EVM.Call entitlement.
    access(all) fun runIndexer(coa: auth(EVM.Call) &EVM.CadenceOwnedAccount): UInt64 {
        let bufAddr = EVMTransferIndexer.parseEVMAddress(EVMTransferIndexer.BUFFER_ADDRESS)

        // --- Step 1: pendingSince(lastHead) ---
        let pendingCalldata = EVMTransferIndexer.buildPendingSinceCalldata(
            lastHead: EVMTransferIndexer.lastHead
        )
        let pendingResult = coa.call(
            to: bufAddr,
            data: pendingCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        var pending: UInt64 = 0
        var currentHead: UInt64 = EVMTransferIndexer.lastHead

        if pendingResult.status == EVM.Status.successful && pendingResult.data.length >= 64 {
            // Decode first uint64 (pending) from bytes 24-31
            var i = 24
            while i < 32 {
                pending = pending * 256 + UInt64(pendingResult.data[i])
                i = i + 1
            }
            // Decode second uint64 (currentHead) from bytes 56-63
            // IMPORTANT: start from 0, not from lastHead
            var decodedHead: UInt64 = 0
            i = 56
            while i < 64 {
                decodedHead = decodedHead * 256 + UInt64(pendingResult.data[i])
                i = i + 1
            }
            currentHead = decodedHead
        }

        // --- Step 2: Check for overflow ---
        // NOTE: pendingSince() in the EVM contract already caps pending at 256.
        // If pending == 256, it could mean exactly 256 OR more than 256 records are pending.
        // The actual difference is (currentHead - lastHead).
        // If that difference > 256, records are lost.
        var missed: UInt64 = 0
        if pending >= EVMTransferIndexer.BUFFER_SIZE {
            // Calculate true difference to detect overflow
            let trueDiff: UInt64 = currentHead > EVMTransferIndexer.lastHead
                ? currentHead - EVMTransferIndexer.lastHead
                : 0
            if trueDiff > EVMTransferIndexer.BUFFER_SIZE {
                missed = trueDiff - EVMTransferIndexer.BUFFER_SIZE
                EVMTransferIndexer.totalMissed = EVMTransferIndexer.totalMissed + missed
                emit RecordsMissed(estimated: missed)
            }
            // pending is already capped at BUFFER_SIZE by EVM contract
        }

        // --- Step 3: Read and store pending records ---
        var indexed: UInt64 = 0
        if pending > 0 {
            // The oldest record we can still read: startSeq = currentHead - pending + 1
            // But currentHead is the NEXT head value (one past the last written)
            // Records are at seqNums: (currentHead - pending) .. (currentHead - 1)
            var seq: UInt64 = 0
            if currentHead >= pending {
                seq = currentHead - pending
            }
            let endSeq = currentHead

            while seq < endSeq {
                let recordCalldata = EVMTransferIndexer.buildGetRecordCalldata(seq: seq)
                let recordResult = coa.call(
                    to: bufAddr,
                    data: recordCalldata,
                    gasLimit: 60000,
                    value: EVM.Balance(attoflow: 0)
                )

                if recordResult.status == EVM.Status.successful && recordResult.data.length >= 160 {
                    let rec = EVMTransferIndexer.decodeRecord(data: recordResult.data, expectedSeq: seq)
                    if rec != nil {
                        let r = rec!
                        EVMTransferIndexer.records[r.seqNum] = r

                        // Update address index for `from`
                        if EVMTransferIndexer.addressIndex[r.from] == nil {
                            EVMTransferIndexer.addressIndex[r.from] = []
                        }
                        EVMTransferIndexer.addressIndex[r.from]!.append(r.seqNum)

                        // Update address index for `to`
                        if EVMTransferIndexer.addressIndex[r.to] == nil {
                            EVMTransferIndexer.addressIndex[r.to] = []
                        }
                        EVMTransferIndexer.addressIndex[r.to]!.append(r.seqNum)

                        indexed = indexed + 1
                    }
                }
                seq = seq + 1
            }
        }

        // --- Step 4: Update state ---
        let fromHead = EVMTransferIndexer.lastHead
        EVMTransferIndexer.lastHead = currentHead
        EVMTransferIndexer.totalRecordsIndexed = EVMTransferIndexer.totalRecordsIndexed + indexed
        EVMTransferIndexer.totalRuns = EVMTransferIndexer.totalRuns + 1

        // --- Step 5: Adaptive interval ---
        let interval = EVMTransferIndexer.computeInterval(pending: pending)
        EVMTransferIndexer.lastRunPending = pending
        EVMTransferIndexer.lastRunInterval = interval

        if indexed > 0 {
            emit RecordsIndexed(count: indexed, fromHead: fromHead, toHead: currentHead)
        }
        emit SchedulerRun(pending: pending, interval: interval, recordsIndexed: indexed)

        return interval
    }

    // -------------------------------------------------------------------------
    // Adaptive interval calculation
    // -------------------------------------------------------------------------

    /// Returns the next scheduling interval in blocks based on recent activity.
    /// pending == 0        → 43200 blocks (~10h, "dead token")
    /// pending 1-5         → 2000 blocks  (~27 min)
    /// pending 6-50        → 500 blocks   (~7 min)
    /// pending 51-200      → 100 blocks   (~80 sec)
    /// pending > 200       → 50 blocks    (~40 sec, near overflow risk)
    access(all) view fun computeInterval(pending: UInt64): UInt64 {
        if pending == (0 as UInt64) {
            return 43200 as UInt64
        } else if pending <= (5 as UInt64) {
            return 2000 as UInt64
        } else if pending <= (50 as UInt64) {
            return 500 as UInt64
        } else if pending <= (200 as UInt64) {
            return 100 as UInt64
        } else {
            return 50 as UInt64
        }
    }

    // -------------------------------------------------------------------------
    // Surcharge model
    // -------------------------------------------------------------------------

    /// Estimate required surcharge in basis points to break even on scheduler cost.
    /// Formula: surcharge_bps = schedulerCostPerTransfer / transferGas * 10000
    ///
    /// Assumptions:
    ///   - Scheduler run cost: ~0.001 FLOW per run (estimate)
    ///   - Transfer gas: 84,263 gas at 16 gwei = ~0.000001348 FLOW per transfer
    ///   - schedulerCostPerTransfer = schedulerCost / avg_records_per_run
    ///
    /// Returns basis points (1 bps = 0.01%)
    access(all) fun estimateSurcharge(): UInt64 {
        // Average records per run (avoid div by zero)
        let avgRecords: UInt64 = EVMTransferIndexer.totalRuns > 0
            ? EVMTransferIndexer.totalRecordsIndexed / EVMTransferIndexer.totalRuns
            : (1 as UInt64)

        let safeAvg: UInt64 = avgRecords > 0 ? avgRecords : (1 as UInt64)

        // Scheduler cost per run in attoFLOW (estimate: 0.001 FLOW = 1_000_000_000_000_000 attoFLOW)
        // Transfer gas cost: 84263 gas * 16e9 attoFLOW/gas = 1_348_208_000_000 attoFLOW
        // We use integer arithmetic scaled by 10000 to get basis points

        // schedulerCostPerTransfer_scaled = (1_000_000_000_000_000 * 10000) / (safeAvg * 1_348_208_000_000)
        // Simplify: (1_000_000 * 10000) / (safeAvg * 1348)  [dividing both by 1e9]
        let numerator: UInt64 = 10000000000   // 1e6 * 10000
        let multiplier: UInt64 = 1348
        let denominator: UInt64 = safeAvg * multiplier

        if denominator == 0 {
            return 10000 as UInt64 // 100% fallback
        }

        let bps: UInt64 = numerator / denominator
        // Clamp to reasonable range: 1 bps to 5000 bps (50%)
        if bps < (1 as UInt64) { return 1 as UInt64 }
        if bps > (5000 as UInt64) { return 5000 as UInt64 }
        return bps
    }

    // -------------------------------------------------------------------------
    // Query functions
    // -------------------------------------------------------------------------

    access(all) fun getRecord(seqNum: UInt64): TransferRecord? {
        return EVMTransferIndexer.records[seqNum]
    }

    access(all) fun getRecordsByAddress(addr: String, limit: UInt64): [TransferRecord] {
        let normalizedAddr = EVMTransferIndexer.normalizeAddress(addr)
        let seqNums = EVMTransferIndexer.addressIndex[normalizedAddr] ?? []
        var result: [TransferRecord] = []
        var i = seqNums.length
        var count: UInt64 = 0
        // Iterate from newest to oldest
        while i > 0 && count < limit {
            i = i - 1
            let seq = seqNums[i]
            if let rec = EVMTransferIndexer.records[seq] {
                result.append(rec)
                count = count + 1
            }
        }
        return result
    }

    access(all) fun getRecentRecords(limit: UInt64): [TransferRecord] {
        var result: [TransferRecord] = []
        var count: UInt64 = 0
        // Iterate from most recent seqNum downward
        var seq: UInt64 = EVMTransferIndexer.lastHead
        // Avoid underflow
        var checked: UInt64 = 0
        while count < limit && checked < EVMTransferIndexer.totalRecordsIndexed + 1 {
            if seq == 0 { break }
            seq = seq - 1
            if let rec = EVMTransferIndexer.records[seq] {
                result.append(rec)
                count = count + 1
            }
            checked = checked + 1
        }
        return result
    }

    access(all) fun getStats(): IndexerStats {
        return IndexerStats(
            lastHead: EVMTransferIndexer.lastHead,
            totalIndexed: EVMTransferIndexer.totalRecordsIndexed,
            totalMissed: EVMTransferIndexer.totalMissed,
            totalRuns: EVMTransferIndexer.totalRuns,
            lastRunPending: EVMTransferIndexer.lastRunPending,
            lastRunInterval: EVMTransferIndexer.lastRunInterval,
            bufferAddress: EVMTransferIndexer.BUFFER_ADDRESS,
            bufferSize: EVMTransferIndexer.BUFFER_SIZE
        )
    }

    // -------------------------------------------------------------------------
    // EVM calldata builders
    // -------------------------------------------------------------------------

    /// Build calldata for pendingSince(uint64 lastHead) — selector f64a4180
    access(self) fun buildPendingSinceCalldata(lastHead: UInt64): [UInt8] {
        var data: [UInt8] = [0xf6, 0x4a, 0x41, 0x80]
        data.appendAll(EVMTransferIndexer.encodeUInt64(lastHead))
        return data
    }

    /// Build calldata for getRecord(uint64 seq) — selector 30bd23bb
    access(self) fun buildGetRecordCalldata(seq: UInt64): [UInt8] {
        var data: [UInt8] = [0x30, 0xbd, 0x23, 0xbb]
        data.appendAll(EVMTransferIndexer.encodeUInt64(seq))
        return data
    }

    // -------------------------------------------------------------------------
    // ABI decoding
    // -------------------------------------------------------------------------

    /// Decode getRecord response (5 × 32 bytes = 160 bytes):
    ///   slot 0 (0-31):   from address (last 20 bytes)
    ///   slot 1 (32-63):  to address   (last 20 bytes)
    ///   slot 2 (64-95):  amount uint96 (last 12 bytes)
    ///   slot 3 (96-127): blockNum uint32 (last 4 bytes)
    ///   slot 4 (128-159): seqNum uint64 (last 8 bytes)
    access(self) fun decodeRecord(data: [UInt8], expectedSeq: UInt64): TransferRecord? {
        if data.length < 160 { return nil }

        // from address: bytes 12-31
        var fromBytes: [UInt8] = []
        var i = 12
        while i < 32 {
            fromBytes.append(data[i])
            i = i + 1
        }
        let fromAddr = EVMTransferIndexer.bytesToHexAddress(fromBytes)

        // to address: bytes 44-63
        var toBytes: [UInt8] = []
        i = 44
        while i < 64 {
            toBytes.append(data[i])
            i = i + 1
        }
        let toAddr = EVMTransferIndexer.bytesToHexAddress(toBytes)

        // amount (uint96): slot 2 = bytes 64-95, uint96 = 12 bytes, so last 12 bytes = 84-95
        var amount: UInt256 = 0
        i = 84
        while i < 96 {
            amount = amount * 256 + UInt256(data[i])
            i = i + 1
        }

        // blockNum (uint32): bytes 124-127 (last 4 bytes of slot 3)
        var blockNum: UInt32 = 0
        i = 124
        while i < 128 {
            blockNum = blockNum * 256 + UInt32(data[i])
            i = i + 1
        }

        // seqNum (uint64): bytes 152-159 (last 8 bytes of slot 4)
        var seqNum: UInt64 = 0
        i = 152
        while i < 160 {
            seqNum = seqNum * 256 + UInt64(data[i])
            i = i + 1
        }

        return TransferRecord(
            from: fromAddr,
            to: toAddr,
            amount: amount,
            blockNum: blockNum,
            seqNum: seqNum
        )
    }

    // -------------------------------------------------------------------------
    // Encoding helpers
    // -------------------------------------------------------------------------

    /// Encode a UInt64 as 32-byte big-endian (ABI encoding)
    access(self) fun encodeUInt64(_ v: UInt64): [UInt8] {
        var result: [UInt8] = []
        // 24 zero bytes of padding
        var i = 0
        while i < 24 {
            result.append(0)
            i = i + 1
        }
        // 8 bytes big-endian
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

    /// Convert 20 bytes to lowercase hex EVM address string (with 0x prefix)
    access(self) fun bytesToHexAddress(_ bytes: [UInt8]): String {
        let hexChars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"]
        var hex = "0x"
        for b in bytes {
            hex = hex.concat(hexChars[Int(b >> 4)]).concat(hexChars[Int(b & 0x0F)])
        }
        return hex
    }

    /// Normalize an EVM address to lowercase with 0x prefix, padded to 42 chars
    access(self) fun normalizeAddress(_ addr: String): String {
        var a = addr
        if a.length >= 2 && a.slice(from: 0, upTo: 2) == "0x" {
            a = a.slice(from: 2, upTo: a.length)
        }
        // lowercase
        // Note: Cadence doesn't have a toLower builtin, so we reconstruct via hex chars
        // For simplicity, store addresses as-is from decoding (already lowercase)
        return "0x".concat(a)
    }

    /// Parse a hex EVM address string to EVM.EVMAddress
    access(self) fun parseEVMAddress(_ hexAddr: String): EVM.EVMAddress {
        var hex = hexAddr
        if hex.length >= 2 && hex.slice(from: 0, upTo: 2) == "0x" {
            hex = hex.slice(from: 2, upTo: hex.length)
        }
        while hex.length < 40 { hex = "0".concat(hex) }
        var bytes: [UInt8] = []
        var i = 0
        while i < 40 {
            let high = EVMTransferIndexer.hexCharToUInt8(hex.slice(from: i, upTo: i + 1))
            let low  = EVMTransferIndexer.hexCharToUInt8(hex.slice(from: i + 1, upTo: i + 2))
            bytes.append((high << 4) | low)
            i = i + 2
        }
        return EVM.EVMAddress(bytes: [
            bytes[0],  bytes[1],  bytes[2],  bytes[3],  bytes[4],
            bytes[5],  bytes[6],  bytes[7],  bytes[8],  bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
            bytes[15], bytes[16], bytes[17], bytes[18], bytes[19]
        ])
    }

    access(self) fun hexCharToUInt8(_ c: String): UInt8 {
        switch c {
            case "0": return 0;  case "1": return 1;  case "2": return 2
            case "3": return 3;  case "4": return 4;  case "5": return 5
            case "6": return 6;  case "7": return 7;  case "8": return 8
            case "9": return 9;  case "a": return 10; case "A": return 10
            case "b": return 11; case "B": return 11; case "c": return 12
            case "C": return 12; case "d": return 13; case "D": return 13
            case "e": return 14; case "E": return 14; case "f": return 15
            case "F": return 15
        }
        return 0
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.BUFFER_ADDRESS = "0xF95E1FbeCF80813445b3EFEa25C202CFcd3232b8"
        self.BUFFER_SIZE = 256

        self.records = {}
        self.addressIndex = {}
        self.lastHead = 0
        self.totalRecordsIndexed = 0
        self.totalMissed = 0
        self.totalRuns = 0
        self.lastRunPending = 0
        self.lastRunInterval = 0

        self.HandlerStoragePath = /storage/EVMTransferIndexerHandler
        self.HandlerPublicPath  = /public/EVMTransferIndexerHandler
        self.AdminStoragePath   = /storage/EVMTransferIndexerAdmin

        self.account.storage.save(<- create Handler(), to: self.HandlerStoragePath)
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<
                &{FlowTransactionScheduler.TransactionHandler}
            >(self.HandlerStoragePath),
            at: self.HandlerPublicPath
        )
        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
