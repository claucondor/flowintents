// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EVMBidRelay
/// @notice Allows EVM-only users to create intents and solvers to post bids for FlowIntents.
/// A Cadence relayer reads these via COA calls and forwards to IntentMarketplaceV0_3 / BidManagerV0_3.
contract EVMBidRelay {

    // =========================================================================
    // Structs
    // =========================================================================

    /// @notice An intent created by an EVM user. Funds are locked here until a Cadence
    ///         relayer calls releaseToCOA(), which bridges them to Cadence and creates
    ///         a native Cadence intent in IntentMarketplaceV0_3.
    struct EVMIntent {
        address creator;
        uint256 amount;        // attoFLOW locked (principal only, not gas escrow)
        uint8   intentType;   // 0 = yield, 1 = swap
        uint256 targetAPY;    // basis points, for yield intents (e.g. 500 = 5%)
        uint256 minAmountOut; // minimum output amount, for swap intents (in token decimals)
        uint256 maxFeeBPS;    // max fee in basis points
        uint256 durationDays;
        uint256 expiryBlock;
        uint256 gasEscrow;    // attoFLOW reserved for gas (paid to solver on execution)
        bool    released;     // true once releaseToCOA has been called
    }

    /// @notice A bid from an EVM-only solver for a Cadence intent.
    struct EVMBid {
        address solver;           // msg.sender
        uint256 intentId;         // Cadence intent ID (assigned by IntentMarketplaceV0_3)
        uint256 offeredAPY;       // basis points, for yield intents
        uint256 offeredAmountOut; // for swap intents (in token decimals)
        uint256 maxGasBid;        // in attoFLOW
        bytes   encodedBatch;     // ABI-encoded StrategyStep[] for FlowIntentsComposerV4
        uint256 submittedAt;      // block.timestamp
        bool    active;           // false if withdrawn
    }

    // =========================================================================
    // Storage
    // =========================================================================

    /// EVM intents: evmIntentId -> EVMIntent
    mapping(uint256 => EVMIntent) public evmIntents;
    uint256 public nextEVMIntentId;

    /// Bids: intentId (Cadence) -> bids array
    mapping(uint256 => EVMBid[]) public bidsByIntent;
    /// solver -> Cadence intentIds they bid on
    mapping(address => uint256[]) public bidsBysolver;

    // =========================================================================
    // Events
    // =========================================================================

    event EVMIntentSubmitted(
        uint256 indexed evmIntentId,
        address indexed creator,
        uint256 amount,
        uint8   intentType
    );

    event EVMIntentReleased(
        uint256 indexed evmIntentId,
        address indexed releasedTo,
        uint256 totalAmount
    );

    event BidSubmitted(
        uint256 indexed intentId,
        address indexed solver,
        uint256 offeredAPY,
        uint256 maxGasBid
    );

    event BidWithdrawn(uint256 indexed intentId, address indexed solver);

    // =========================================================================
    // EVM Intent functions
    // =========================================================================

    /// @notice Submit a new EVM-originated intent, locking principal + gas escrow.
    /// @param intentType   0 = yield, 1 = swap
    /// @param targetAPY    For yield intents: target APY in basis points (e.g. 500 = 5%)
    /// @param minAmountOut For swap intents: minimum output amount
    /// @param maxFeeBPS    Maximum fee in basis points
    /// @param durationDays How long the strategy should run
    /// @param expiryBlock  Block number after which the intent expires (no winner selected)
    /// @param gasEscrow    attoFLOW reserved for gas (must be <= msg.value)
    /// @return evmIntentId The ID assigned to this EVM intent
    /// @dev msg.value = principal amount + gasEscrow (total FLOW locked in this contract)
    function submitIntent(
        uint8   intentType,
        uint256 targetAPY,
        uint256 minAmountOut,
        uint256 maxFeeBPS,
        uint256 durationDays,
        uint256 expiryBlock,
        uint256 gasEscrow
    ) external payable returns (uint256 evmIntentId) {
        require(msg.value > gasEscrow, "msg.value must exceed gasEscrow");
        require(durationDays > 0, "durationDays must be positive");
        require(expiryBlock > block.number, "expiryBlock must be in the future");
        if (intentType == 0) {
            require(targetAPY > 0, "targetAPY must be positive for yield intents");
        } else if (intentType == 1) {
            require(minAmountOut > 0, "minAmountOut must be positive for swap intents");
        } else {
            revert("invalid intentType");
        }

        evmIntentId = nextEVMIntentId++;
        uint256 principal = msg.value - gasEscrow;

        evmIntents[evmIntentId] = EVMIntent({
            creator:      msg.sender,
            amount:       principal,
            intentType:   intentType,
            targetAPY:    targetAPY,
            minAmountOut: minAmountOut,
            maxFeeBPS:    maxFeeBPS,
            durationDays: durationDays,
            expiryBlock:  expiryBlock,
            gasEscrow:    gasEscrow,
            released:     false
        });

        emit EVMIntentSubmitted(evmIntentId, msg.sender, principal, intentType);
    }

    /// @notice Releases the locked FLOW (principal + gasEscrow) to the caller.
    ///         Only callable once per intent. The Cadence relayer's COA calls this via coa.call().
    ///         After this call, the relayer bridges the FLOW to Cadence and creates a native intent.
    /// @param evmIntentId The EVM intent ID to release
    function releaseToCOA(uint256 evmIntentId) external {
        EVMIntent storage intent = evmIntents[evmIntentId];
        require(intent.creator != address(0), "intent does not exist");
        require(!intent.released, "already released");

        intent.released = true;
        uint256 total = intent.amount + intent.gasEscrow;

        emit EVMIntentReleased(evmIntentId, msg.sender, total);

        // Transfer total locked FLOW to the caller (the COA)
        (bool ok,) = payable(msg.sender).call{value: total}("");
        require(ok, "FLOW transfer failed");
    }

    // =========================================================================
    // Bid functions
    // =========================================================================

    /// @notice Submit a bid for a Cadence intent (for yield or swap intents).
    ///         For yield intents: set offeredAPY > 0 and offeredAmountOut = 0.
    ///         For swap intents: set offeredAmountOut > 0 and offeredAPY = 0.
    /// @param intentId        Cadence intent ID (from IntentMarketplaceV0_3)
    /// @param offeredAPY      Offered APY in basis points (0 for swap bids)
    /// @param offeredAmountOut Offered output amount (0 for yield bids)
    /// @param maxGasBid       Max gas bid in attoFLOW
    /// @param encodedBatch    ABI-encoded StrategyStep[] for FlowIntentsComposerV4
    function submitBid(
        uint256 intentId,
        uint256 offeredAPY,
        uint256 offeredAmountOut,
        uint256 maxGasBid,
        bytes calldata encodedBatch
    ) external {
        require(offeredAPY > 0 || offeredAmountOut > 0, "must provide offeredAPY or offeredAmountOut");
        require(maxGasBid > 0, "maxGasBid must be positive");
        require(encodedBatch.length > 0, "encodedBatch required");

        bidsByIntent[intentId].push(EVMBid({
            solver:           msg.sender,
            intentId:         intentId,
            offeredAPY:       offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid:        maxGasBid,
            encodedBatch:     encodedBatch,
            submittedAt:      block.timestamp,
            active:           true
        }));

        bidsBysolver[msg.sender].push(intentId);

        emit BidSubmitted(intentId, msg.sender, offeredAPY, maxGasBid);
    }

    /// @notice Withdraw (deactivate) a bid. Only callable by the bid's solver.
    function withdrawBid(uint256 intentId, uint256 bidIndex) external {
        EVMBid storage bid = bidsByIntent[intentId][bidIndex];
        require(bid.solver == msg.sender, "Not your bid");
        bid.active = false;
        emit BidWithdrawn(intentId, msg.sender);
    }

    // =========================================================================
    // View functions
    // =========================================================================

    function getBidsForIntent(uint256 intentId) external view returns (EVMBid[] memory) {
        return bidsByIntent[intentId];
    }

    function getActiveBidCount(uint256 intentId) external view returns (uint256 count) {
        EVMBid[] storage bids = bidsByIntent[intentId];
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].active) count++;
        }
    }

    function getEVMIntent(uint256 evmIntentId) external view returns (EVMIntent memory) {
        return evmIntents[evmIntentId];
    }
}
