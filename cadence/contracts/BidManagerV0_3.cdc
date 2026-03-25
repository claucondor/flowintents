/// BidManagerV0_3.cdc
/// Manages the bidding competition between registered AI solver agents.
/// Gas escrow model: user deposits fixed gas budget, solver keeps ENTIRE escrow on execution.
/// Solver profit = gasEscrow - actual gas cost (internal to solver).
/// Scoring:
///   Combined score = (APY-based score * 0.7) + (gasEfficiencyScore * 0.3)
///   gasEfficiencyScore = 1.0 / (maxGasBid + 0.001)
///   Lower maxGasBid = higher score (solvers compete to request less from user)
///   Swap: score = (offeredAmountOut * reputationMultiplier * 0.7) + (gasEfficiencyScore * 0.3)
/// Tie-breaking: earliest submittedAt wins.

import IntentMarketplaceV0_3 from "IntentMarketplaceV0_3"
import SolverRegistryV0_1 from "SolverRegistryV0_1"

access(all) contract BidManagerV0_3 {

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
        targetChain: String?,
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

        // ---- Yield / BridgeYield ----
        access(all) let offeredAPY: UFix64?         // nil for Swap bids

        // ---- Swap ----
        access(all) let offeredAmountOut: UFix64?   // nil for Yield/BridgeYield bids
        access(all) let estimatedFeeBPS: UInt64?    // fee in basis points (optional)

        // ---- BridgeYield ----
        access(all) let targetChain: String?        // e.g. "ethereum", "base" (nil for Flow-native)

        // ---- V0_3 Gas Escrow Fields ----
        access(all) let maxGasBid: UFix64           // max gas escrow the solver requests from user

        /// JSON-encoded strategy description
        access(all) let strategy: String
        /// ABI-encoded BatchStep[] for FlowIntentsComposer.sol
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
            estimatedFeeBPS: UInt64?,
            targetChain: String?,
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
            self.estimatedFeeBPS = estimatedFeeBPS
            self.targetChain = targetChain
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
    /// bidID -> Bid resource
    access(self) var bids: @{UInt64: Bid}
    /// intentID -> [bidID] -- all bids for an intent
    access(self) var intentBids: {UInt64: [UInt64]}
    /// intentID -> winning bidID (set after selectWinner)
    access(self) var winners: {UInt64: UInt64}
    /// (intentID, solverAddress) -> bidID -- prevent duplicate bids
    access(self) var solverBidForIntent: {String: UInt64}

    access(all) let BidManagerStoragePath: StoragePath
    access(all) let BidManagerPublicPath:  PublicPath

    // -------------------------------------------------------------------------
    // Core functions
    // -------------------------------------------------------------------------

    /// Submit a bid for an open intent.
    /// Solver must be registered in SolverRegistryV0_1.
    access(all) fun submitBid(
        intentID: UInt64,
        solverAddress: Address,
        offeredAPY: UFix64?,
        offeredAmountOut: UFix64?,
        estimatedFeeBPS: UInt64?,
        targetChain: String?,
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
        let intent = IntentMarketplaceV0_3.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(
            intent.status == IntentMarketplaceV0_3.IntentStatus.Open,
            message: "Intent is not open for bids"
        )

        // Type-specific validation
        let intentType = intent.intentType
        if intentType == IntentMarketplaceV0_3.IntentType.Yield || intentType == IntentMarketplaceV0_3.IntentType.BridgeYield {
            assert(offeredAPY != nil, message: "offeredAPY required for Yield/BridgeYield intents")
            assert((offeredAPY ?? 0.0) > 0.0, message: "offeredAPY must be positive")
            if intentType == IntentMarketplaceV0_3.IntentType.BridgeYield {
                if let minAPY = intent.minAPY {
                    assert((offeredAPY ?? 0.0) >= minAPY, message: "offeredAPY below intent minAPY")
                }
            }
        } else if intentType == IntentMarketplaceV0_3.IntentType.Swap {
            assert(offeredAmountOut != nil, message: "offeredAmountOut required for Swap intents")
            assert((offeredAmountOut ?? 0.0) > 0.0, message: "offeredAmountOut must be positive")
            if let minOut = intent.minAmountOut {
                assert((offeredAmountOut ?? 0.0) >= minOut, message: "offeredAmountOut below intent minAmountOut")
            }
        }

        // Prevent duplicate bids from same solver on same intent
        let dedupeKey = intentID.toString().concat("-").concat(solverAddress.toString())
        assert(
            BidManagerV0_3.solverBidForIntent[dedupeKey] == nil,
            message: "Solver already submitted a bid for this intent"
        )

        // Compute score: combined APY/amount score (70%) + gas efficiency (30%)
        let reputationMultiplier = SolverRegistryV0_1.getReputationMultiplier(cadenceAddress: solverAddress)

        // Gas efficiency score: lower maxGasBid = higher score (solvers compete to request less)
        // gasEfficiencyScore = 1.0 / (maxGasBid + 0.001)
        let gasEfficiencyScore = 1.0 / (maxGasBid + 0.001)

        var score: UFix64 = 0.0
        if intentType == IntentMarketplaceV0_3.IntentType.Swap {
            let baseScore = (offeredAmountOut ?? 0.0) * reputationMultiplier
            score = (baseScore * 0.7) + (gasEfficiencyScore * 0.3)
        } else {
            let baseScore = (offeredAPY ?? 0.0) * reputationMultiplier
            score = (baseScore * 0.7) + (gasEfficiencyScore * 0.3)
        }

        // Get solver's EVM address
        let solverInfo = SolverRegistryV0_1.getSolver(cadenceAddress: solverAddress)!
        let solverEVMAddress = solverInfo.evmAddress

        let bidID = BidManagerV0_3.totalBids
        let bid <- create Bid(
            id: bidID,
            intentID: intentID,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            estimatedFeeBPS: estimatedFeeBPS,
            targetChain: targetChain,
            maxGasBid: maxGasBid,
            strategy: strategy,
            encodedBatch: encodedBatch,
            score: score
        )

        BidManagerV0_3.bids[bidID] <-! bid
        BidManagerV0_3.totalBids = BidManagerV0_3.totalBids + 1

        // Index by intent
        if BidManagerV0_3.intentBids[intentID] == nil {
            BidManagerV0_3.intentBids[intentID] = []
        }
        BidManagerV0_3.intentBids[intentID]!.append(bidID)
        BidManagerV0_3.solverBidForIntent[dedupeKey] = bidID

        emit BidSubmitted(
            bidID: bidID,
            intentID: intentID,
            intentType: intent.intentType.rawValue,
            solverAddress: solverAddress,
            solverEVMAddress: solverEVMAddress,
            offeredAPY: offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid: maxGasBid,
            targetChain: targetChain,
            score: score
        )

        return bidID
    }

    /// Select the winner for an intent.
    /// Winning criteria: highest score. Tie -> earliest submittedAt.
    access(all) fun selectWinner(intentID: UInt64, callerAddress: Address) {
        // Verify intent exists and is Open
        let intent = IntentMarketplaceV0_3.getIntent(id: intentID)
            ?? panic("Intent does not exist")
        assert(intent.status == IntentMarketplaceV0_3.IntentStatus.Open, message: "Intent not open")
        assert(
            intent.intentOwner == callerAddress,
            message: "Only the intent owner can select the winner"
        )

        let bidIDs = BidManagerV0_3.intentBids[intentID] ?? panic("No bids for this intent")
        assert(bidIDs.length > 0, message: "No bids submitted for this intent")

        // Find highest-scoring bid; ties broken by earliest submittedAt
        var winningBidID: UInt64 = bidIDs[0]
        var winningScore: UFix64 = 0.0
        var winningTime: UFix64 = UFix64.max

        for bidID in bidIDs {
            let bid = (&BidManagerV0_3.bids[bidID] as &Bid?)!
            if bid.score > winningScore {
                winningScore = bid.score
                winningBidID = bidID
                winningTime = bid.submittedAt
            } else if bid.score == winningScore && bid.submittedAt < winningTime {
                winningBidID = bidID
                winningTime = bid.submittedAt
            }
        }

        BidManagerV0_3.winners[intentID] = winningBidID

        // Update intent status via Marketplace public capability
        let marketplace = getAccount(self.account.address)
            .capabilities.borrow<&IntentMarketplaceV0_3.Marketplace>(
                IntentMarketplaceV0_3.MarketplacePublicPath
            ) ?? panic("Cannot borrow MarketplaceV0_3")
        marketplace.setBidSelectedOnIntent(id: intentID, bidID: winningBidID)

        let winningBid = (&BidManagerV0_3.bids[winningBidID] as &Bid?)!

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
        return &BidManagerV0_3.bids[bidID] as &Bid?
    }

    access(all) fun getWinningBid(intentID: UInt64): &Bid? {
        if let winnerID = BidManagerV0_3.winners[intentID] {
            return &BidManagerV0_3.bids[winnerID] as &Bid?
        }
        return nil
    }

    access(all) fun getBidsForIntent(intentID: UInt64): [UInt64] {
        return BidManagerV0_3.intentBids[intentID] ?? []
    }

    access(all) fun getWinningBidID(intentID: UInt64): UInt64? {
        return BidManagerV0_3.winners[intentID]
    }

    access(all) fun getEncodedBatch(intentID: UInt64): [UInt8]? {
        if let winnerID = BidManagerV0_3.winners[intentID] {
            if let bid = &BidManagerV0_3.bids[winnerID] as &Bid? {
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

        self.BidManagerStoragePath = /storage/FlowIntentsBidManagerV3
        self.BidManagerPublicPath  = /public/FlowIntentsBidManagerV3
    }
}
