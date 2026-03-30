/// BidManagerV0_4.cdc
/// Manages bidding for V0_4 intents (user-executed model).
///
/// Key differences from V0_3:
///   - References IntentMarketplaceV0_4 instead of V0_3
///   - No minAmountOut assertion (solver offers real market rate, user decides)
///   - Solver bids with offeredAmountOut or offeredAPY
///   - Scoring unchanged: (APY/amount * reputation * 0.7) + (gasEfficiency * 0.3)
///
/// IMPORTANT: This is a NEW contract — does NOT modify V0_3.

import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

access(all) contract BidManagerV0_4 {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event BidSubmitted(
        bidID: UInt64,
        intentID: UInt64,
        intentType: UInt8,
        solverAddress: Address,
        solverEVMAddress: String,
        offeredAPY: UFix64?,
        offeredAmountOut: UFix64?,
        maxGasBid: UFix64,
        score: UFix64
    )

    access(all) event WinnerSelected(
        intentID: UInt64,
        winningBidID: UInt64,
        solverAddress: Address,
        solverEVMAddress: String,
        offeredAPY: UFix64?,
        offeredAmountOut: UFix64?,
        maxGasBid: UFix64,
        score: UFix64
    )

    // -------------------------------------------------------------------------
    // Bid Resource
    // -------------------------------------------------------------------------

    access(all) resource Bid {
        access(all) let id: UInt64
        access(all) let intentID: UInt64
        access(all) let solverAddress: Address
        access(all) let solverEVMAddress: String

        // ---- Yield ----
        access(all) let offeredAPY: UFix64?

        // ---- Swap ----
        access(all) let offeredAmountOut: UFix64?

        // ---- Gas ----
        access(all) let maxGasBid: UFix64

        /// JSON-encoded strategy description
        access(all) let strategy: String
        /// ABI-encoded StrategyStep[] for FlowIntentsComposerV4
        access(all) let encodedBatch: [UInt8]

        access(all) let submittedAt: UFix64
        access(all) let score: UFix64

        init(
            id: UInt64,
            intentID: UInt64,
            solverAddress: Address,
            solverEVMAddress: String,
            offeredAPY: UFix64?,
            offeredAmountOut: UFix64?,
            maxGasBid: UFix64,
            strategy: String,
            encodedBatch: [UInt8],
            score: UFix64
        ) {
            self.id = id
            self.intentID = intentID
            self.solverAddress = solverAddress
            self.solverEVMAddress = solverEVMAddress
            self.offeredAPY = offeredAPY
            self.offeredAmountOut = offeredAmountOut
            self.maxGasBid = maxGasBid
            self.strategy = strategy
            self.encodedBatch = encodedBatch
            self.submittedAt = getCurrentBlock().timestamp
            self.score = score
        }
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    access(all) var totalBids: UInt64
    access(self) var bids: @{UInt64: Bid}
    access(self) var intentBids: {UInt64: [UInt64]}
    access(self) var winners: {UInt64: UInt64}
    access(self) var solverBidForIntent: {String: UInt64}

    access(all) let BidManagerStoragePath: StoragePath
    access(all) let BidManagerPublicPath:  PublicPath

    // -------------------------------------------------------------------------
    // Core functions
    // -------------------------------------------------------------------------

    /// Submit a bid for an open V0_4 intent.
    /// Solver must be registered in SolverRegistryV0_1.
    access(all) fun submitBid(
        intentID: UInt64,
        solverAddress: Address,
        offeredAPY: UFix64?,
        offeredAmountOut: UFix64?,
        maxGasBid: UFix64,
        strategy: String,
        encodedBatch: [UInt8]
    ): UInt64 {
        pre {
            encodedBatch.length > 0: "Encoded batch cannot be empty"
            strategy.length > 0:     "Strategy description required"
            maxGasBid > 0.0:         "maxGasBid must be positive"
        }

        // Verify solver is registered
        assert(
            SolverRegistryV0_1.isRegistered(cadenceAddress: solverAddress),
            message: "Solver not registered in SolverRegistryV0_1"
        )

        // Verify intent is open
        let intent = IntentMarketplaceV0_4.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplaceV0_4.IntentStatus.Open,
            message: "Intent is not open for bids"
        )

        // Type-specific validation
        let intentType = intent.intentType
        if intentType == IntentMarketplaceV0_4.IntentType.Yield {
            assert(offeredAPY != nil, message: "offeredAPY required for Yield intents")
            assert((offeredAPY ?? 0.0) > 0.0, message: "offeredAPY must be positive")
        } else if intentType == IntentMarketplaceV0_4.IntentType.Swap {
            assert(offeredAmountOut != nil, message: "offeredAmountOut required for Swap intents")
            assert((offeredAmountOut ?? 0.0) > 0.0, message: "offeredAmountOut must be positive")
            // No minAmountOut assertion — user decides via selectWinner
        }

        // Prevent duplicate bids
        let dedupeKey = intentID.toString().concat("-").concat(solverAddress.toString())
        assert(
            BidManagerV0_4.solverBidForIntent[dedupeKey] == nil,
            message: "Solver already submitted a bid for this intent"
        )

        // Compute score: (base * reputation * 0.7) + (gasEfficiency * 0.3)
        let reputationMultiplier = SolverRegistryV0_1.getReputationMultiplier(cadenceAddress: solverAddress)
        let gasEfficiencyScore = 1.0 / (maxGasBid + 0.001)

        var score: UFix64 = 0.0
        if intentType == IntentMarketplaceV0_4.IntentType.Swap {
            let baseScore = (offeredAmountOut ?? 0.0) * reputationMultiplier
            score = (baseScore * 0.7) + (gasEfficiencyScore * 0.3)
        } else {
            let baseScore = (offeredAPY ?? 0.0) * reputationMultiplier
            score = (baseScore * 0.7) + (gasEfficiencyScore * 0.3)
        }

        // Get solver's EVM address
        let solverInfo = SolverRegistryV0_1.getSolver(cadenceAddress: solverAddress)!
        let solverEVMAddress = solverInfo.evmAddress

        let bidID = BidManagerV0_4.totalBids
        let bid <- create Bid(
            id: bidID,
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch,
            score: score
        )

        BidManagerV0_4.bids[bidID] <-! bid
        BidManagerV0_4.totalBids = BidManagerV0_4.totalBids + 1

        // Index by intent
        if BidManagerV0_4.intentBids[intentID] == nil {
            BidManagerV0_4.intentBids[intentID] = []
        }
        BidManagerV0_4.intentBids[intentID]!.append(bidID)
        BidManagerV0_4.solverBidForIntent[dedupeKey] = bidID

        emit BidSubmitted(
            bidID: bidID,
            intentID: intentID,
            intentType: intent.intentType.rawValue,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid: maxGasBid,
            score: score
        )

        return bidID
    }

    /// Select the winner for an intent.
    /// Only the intent owner can call this.
    /// Winning criteria: highest score. Tie -> earliest submittedAt.
    access(all) fun selectWinner(intentID: UInt64, callerAddress: Address) {
        let intent = IntentMarketplaceV0_4.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(intent.status == IntentMarketplaceV0_4.IntentStatus.Open, message: "Intent not open")
        assert(
            intent.intentOwner == callerAddress,
            message: "Only the intent owner can select the winner"
        )

        let bidIDs = BidManagerV0_4.intentBids[intentID] ?? panic("No bids for this intent")
        assert(bidIDs.length > 0, message: "No bids submitted for this intent")

        var winningBidID: UInt64 = bidIDs[0]
        var winningScore: UFix64 = 0.0
        var winningTime: UFix64 = UFix64.max

        for bidID in bidIDs {
            let bid = (&BidManagerV0_4.bids[bidID] as &Bid?)!
            if bid.score > winningScore {
                winningScore = bid.score
                winningBidID = bidID
                winningTime = bid.submittedAt
            } else if bid.score == winningScore && bid.submittedAt < winningTime {
                winningBidID = bidID
                winningTime = bid.submittedAt
            }
        }

        BidManagerV0_4.winners[intentID] = winningBidID

        // Update intent status via Marketplace public capability
        let marketplace = getAccount(self.account.address)
            .capabilities.borrow<&IntentMarketplaceV0_4.Marketplace>(
                IntentMarketplaceV0_4.MarketplacePublicPath
            ) ?? panic("Cannot borrow MarketplaceV0_4")
        marketplace.setBidSelectedOnIntent(id: intentID, bidID: winningBidID)

        let winningBid = (&BidManagerV0_4.bids[winningBidID] as &Bid?)!

        emit WinnerSelected(
            intentID: intentID,
            winningBidID: winningBidID,
            solverAddress: winningBid.solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            offeredAPY: winningBid.offeredAPY,
            offeredAmountOut: winningBid.offeredAmountOut,
            maxGasBid: winningBid.maxGasBid,
            score: winningBid.score
        )
    }

    // -------------------------------------------------------------------------
    // Read functions
    // -------------------------------------------------------------------------

    access(all) fun getBid(bidID: UInt64): &Bid? {
        return &BidManagerV0_4.bids[bidID] as &Bid?
    }

    access(all) fun getWinningBid(intentID: UInt64): &Bid? {
        if let winnerID = BidManagerV0_4.winners[intentID] {
            return &BidManagerV0_4.bids[winnerID] as &Bid?
        }
        return nil
    }

    access(all) fun getBidsForIntent(intentID: UInt64): [UInt64] {
        return BidManagerV0_4.intentBids[intentID] ?? []
    }

    access(all) fun getWinningBidID(intentID: UInt64): UInt64? {
        return BidManagerV0_4.winners[intentID]
    }

    access(all) fun getBidsBySolver(_ solver: Address): [UInt64] {
        let solverStr = solver.toString()
        let result: [UInt64] = []
        for key in BidManagerV0_4.solverBidForIntent.keys {
            if key.length > solverStr.length {
                let suffix = key.slice(from: key.length - solverStr.length, upTo: key.length)
                if suffix == solverStr {
                    if let bidID = BidManagerV0_4.solverBidForIntent[key] {
                        result.append(bidID)
                    }
                }
            }
        }
        return result
    }

    access(all) fun getEncodedBatch(intentID: UInt64): [UInt8]? {
        if let winnerID = BidManagerV0_4.winners[intentID] {
            if let bid = &BidManagerV0_4.bids[winnerID] as &Bid? {
                return bid.encodedBatch.slice(from: 0, upTo: bid.encodedBatch.length)
            }
        }
        return nil
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        self.totalBids = 0
        self.bids <- {}
        self.intentBids = {}
        self.winners = {}
        self.solverBidForIntent = {}

        self.BidManagerStoragePath = /storage/FlowIntentsBidManagerV4
        self.BidManagerPublicPath  = /public/FlowIntentsBidManagerV4
    }
}
