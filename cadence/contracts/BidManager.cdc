/// BidManager.cdc
/// Manages the bidding competition between registered AI solver agents.
/// Scoring: score = offeredAPY * reputationMultiplier (multiplier from EVM via COA staticCall).
/// Tie-breaking: earliest submittedAt wins.

import IntentMarketplace from "IntentMarketplace"
import SolverRegistry from "SolverRegistry"

access(all) contract BidManager {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event BidSubmitted(
        bidID: UInt64,
        intentID: UInt64,
        solverAddress: Address,
        solverEVMAddress: String,
        offeredAPY: UFix64,
        score: UFix64
    )

    access(all) event WinnerSelected(
        intentID: UInt64,
        winningBidID: UInt64,
        solverAddress: Address,
        solverEVMAddress: String,
        offeredAPY: UFix64,
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
        access(all) let offeredAPY: UFix64
        /// JSON-encoded strategy description (e.g. {"protocol":"IncrementFi","pool":"USDC-FLOW"})
        access(all) let strategy: String
        /// ABI-encoded batch calldata for FlowIntentsComposer.sol
        access(all) let encodedBatch: [UInt8]
        access(all) let submittedAt: UFix64
        access(all) let score: UFix64

        init(
            id: UInt64,
            intentID: UInt64,
            solverAddress: Address,
            solverEVMAddress: String,
            offeredAPY: UFix64,
            strategy: String,
            encodedBatch: [UInt8],
            score: UFix64
        ) {
            self.id = id
            self.intentID = intentID
            self.solverAddress = solverAddress
            self.solverEVMAddress = solverEVMAddress
            self.offeredAPY = offeredAPY
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
    /// bidID -> Bid resource
    access(self) var bids: @{UInt64: Bid}
    /// intentID -> [bidID] — all bids for an intent
    access(self) var intentBids: {UInt64: [UInt64]}
    /// intentID -> winning bidID (set after selectWinner)
    access(self) var winners: {UInt64: UInt64}
    /// (intentID, solverAddress) -> bidID — prevent duplicate bids
    access(self) var solverBidForIntent: {String: UInt64}

    access(all) let BidManagerStoragePath: StoragePath
    access(all) let BidManagerPublicPath:  PublicPath

    // -------------------------------------------------------------------------
    // Core functions
    // -------------------------------------------------------------------------

    /// Submit a bid for an open intent.
    /// Solver must be registered in SolverRegistry.
    access(all) fun submitBid(
        intentID: UInt64,
        solverAddress: Address,
        offeredAPY: UFix64,
        strategy: String,
        encodedBatch: [UInt8]
    ): UInt64 {
        pre {
            offeredAPY > 0.0: "Offered APY must be positive"
            encodedBatch.length > 0: "Encoded batch cannot be empty"
            strategy.length > 0: "Strategy description required"
        }

        // Verify solver is registered
        assert(
            SolverRegistry.isRegistered(cadenceAddress: solverAddress),
            message: "Solver not registered in SolverRegistry"
        )

        // Verify intent is open
        let intent = IntentMarketplace.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplace.IntentStatus.Open,
            message: "Intent is not open for bids"
        )

        // Prevent duplicate bids from same solver on same intent
        let dedupeKey = intentID.toString().concat("-").concat(solverAddress.toString())
        assert(
            BidManager.solverBidForIntent[dedupeKey] == nil,
            message: "Solver already submitted a bid for this intent"
        )

        // Compute score: offeredAPY * reputationMultiplier
        let reputationMultiplier = SolverRegistry.getReputationMultiplier(cadenceAddress: solverAddress)
        let score = offeredAPY * reputationMultiplier

        // Get solver's EVM address
        let solverInfo = SolverRegistry.getSolver(cadenceAddress: solverAddress)!
        let solverEVMAddress = solverInfo.evmAddress

        let bidID = BidManager.totalBids
        let bid <- create Bid(
            id: bidID,
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            strategy: strategy,
            encodedBatch: encodedBatch,
            score: score
        )

        BidManager.bids[bidID] <-! bid
        BidManager.totalBids = BidManager.totalBids + 1

        // Index by intent
        if BidManager.intentBids[intentID] == nil {
            BidManager.intentBids[intentID] = []
        }
        BidManager.intentBids[intentID]!.append(bidID)
        BidManager.solverBidForIntent[dedupeKey] = bidID

        emit BidSubmitted(
            bidID: bidID,
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            score: score
        )

        return bidID
    }

    /// Select the winner for an intent.
    /// Can be called by the intent owner or the protocol (after bid period ends).
    /// Winning criteria: highest score. Tie → earliest submittedAt.
    access(all) fun selectWinner(intentID: UInt64, callerAddress: Address) {
        // Verify intent exists and is Open
        let intent = IntentMarketplace.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(intent.status == IntentMarketplace.IntentStatus.Open, message: "Intent not open")
        assert(
            intent.owner == callerAddress,
            message: "Only the intent owner can select the winner"
        )

        let bidIDs = BidManager.intentBids[intentID] ?? panic("No bids for this intent")
        assert(bidIDs.length > 0, message: "No bids submitted for this intent")

        // Find highest-scoring bid; ties broken by earliest submittedAt
        var winningBidID: UInt64 = bidIDs[0]
        var winningScore: UFix64 = 0.0
        var winningTime: UFix64 = UFix64.max

        for bidID in bidIDs {
            let bid = (&BidManager.bids[bidID] as &Bid?)!
            if bid.score > winningScore {
                winningScore = bid.score
                winningBidID = bidID
                winningTime = bid.submittedAt
            } else if bid.score == winningScore && bid.submittedAt < winningTime {
                winningBidID = bidID
                winningTime = bid.submittedAt
            }
        }

        BidManager.winners[intentID] = winningBidID

        // Update intent status via Marketplace
        let marketplace = IntentMarketplace.account.storage
            .borrow<&IntentMarketplace.Marketplace>(from: IntentMarketplace.MarketplaceStoragePath)
            ?? panic("Cannot borrow Marketplace")
        marketplace.setBidSelectedOnIntent(id: intentID, bidID: winningBidID)

        let winningBid = (&BidManager.bids[winningBidID] as &Bid?)!

        emit WinnerSelected(
            intentID: intentID,
            winningBidID: winningBidID,
            solverAddress: winningBid.solverAddress,
            solverEVMAddress: winningBid.solverEVMAddress,
            offeredAPY: winningBid.offeredAPY,
            score: winningBid.score
        )
    }

    // -------------------------------------------------------------------------
    // Read functions
    // -------------------------------------------------------------------------

    access(all) fun getBid(bidID: UInt64): &Bid? {
        return &BidManager.bids[bidID] as &Bid?
    }

    access(all) fun getWinningBid(intentID: UInt64): &Bid? {
        if let winnerID = BidManager.winners[intentID] {
            return &BidManager.bids[winnerID] as &Bid?
        }
        return nil
    }

    access(all) fun getBidsForIntent(intentID: UInt64): [UInt64] {
        return BidManager.intentBids[intentID] ?? []
    }

    access(all) fun getWinningBidID(intentID: UInt64): UInt64? {
        return BidManager.winners[intentID]
    }

    access(all) fun getEncodedBatch(intentID: UInt64): [UInt8]? {
        if let winnerID = BidManager.winners[intentID] {
            if let bid = &BidManager.bids[winnerID] as &Bid? {
                return bid.encodedBatch
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

        self.BidManagerStoragePath = /storage/FlowIntentsBidManager
        self.BidManagerPublicPath  = /public/FlowIntentsBidManager
    }
}
