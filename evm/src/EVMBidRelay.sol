// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EVMBidRelay
/// @notice Allows EVM-only solvers to post bids for FlowIntents intents.
/// A Cadence relayer reads these bids via COA staticCall and forwards to BidManagerV0_2.
contract EVMBidRelay {
    struct EVMBid {
        address solver;         // msg.sender
        uint256 intentId;       // Cadence intent ID
        uint256 offeredAPY;     // in basis points (e.g. 500 = 5%)
        uint256 maxGasBid;      // in attoFLOW (e.g. 1e17 = 0.1 FLOW)
        bytes encodedBatch;     // ABI-encoded StrategyStep[] for FlowIntentsComposerV2
        uint256 submittedAt;    // block.timestamp
        bool active;            // false if withdrawn
    }

    mapping(uint256 => EVMBid[]) public bidsByIntent;  // intentId -> bids
    mapping(address => uint256[]) public bidsBysolver;  // solver -> intentIds

    event BidSubmitted(uint256 indexed intentId, address indexed solver, uint256 offeredAPY, uint256 maxGasBid);
    event BidWithdrawn(uint256 indexed intentId, address indexed solver);

    function submitBid(
        uint256 intentId,
        uint256 offeredAPY,
        uint256 maxGasBid,
        bytes calldata encodedBatch
    ) external {
        require(offeredAPY > 0, "APY must be positive");
        require(maxGasBid > 0, "maxGasBid must be positive");
        require(encodedBatch.length > 0, "encodedBatch required");

        bidsByIntent[intentId].push(EVMBid({
            solver: msg.sender,
            intentId: intentId,
            offeredAPY: offeredAPY,
            maxGasBid: maxGasBid,
            encodedBatch: encodedBatch,
            submittedAt: block.timestamp,
            active: true
        }));

        bidsBysolver[msg.sender].push(intentId);

        emit BidSubmitted(intentId, msg.sender, offeredAPY, maxGasBid);
    }

    function withdrawBid(uint256 intentId, uint256 bidIndex) external {
        EVMBid storage bid = bidsByIntent[intentId][bidIndex];
        require(bid.solver == msg.sender, "Not your bid");
        bid.active = false;
        emit BidWithdrawn(intentId, msg.sender);
    }

    function getBidsForIntent(uint256 intentId) external view returns (EVMBid[] memory) {
        return bidsByIntent[intentId];
    }

    function getActiveBidCount(uint256 intentId) external view returns (uint256 count) {
        EVMBid[] storage bids = bidsByIntent[intentId];
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].active) count++;
        }
    }
}
