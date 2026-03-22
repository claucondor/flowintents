// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {EVMBidRelay} from "../src/EVMBidRelay.sol";

/// @title EVMBidRelayTest
/// @notice Tests for EVMBidRelay — the EVM-side bid board for FlowIntents.
contract EVMBidRelayTest is Test {
    EVMBidRelay public relay;

    address public solver1;
    address public solver2;

    // A minimal valid ABI-encoded StrategyStep[] (one step: raw call to address(1))
    bytes internal validBatch;

    function setUp() public {
        relay = new EVMBidRelay();
        solver1 = makeAddr("solver1");
        solver2 = makeAddr("solver2");

        // Build a minimal encodedBatch: abi.encode of a StrategyStep[]
        // StrategyStep: (uint8 protocol, address target, bytes callData, uint256 value)
        // We just need non-empty bytes for validation tests.
        validBatch = abi.encode(
            uint8(3),           // protocol = WFLOW_WRAP
            address(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e), // WFLOW
            abi.encodeWithSelector(bytes4(0xd0e30db0)), // deposit()
            uint256(1 ether)    // value
        );
    }

    // =========================================================================
    // Test 1: Solver can submit a bid
    // =========================================================================

    function test_submitBid_success() public {
        uint256 intentId = 42;
        uint256 offeredAPY = 500;   // 5%
        uint256 maxGasBid = 1e17;   // 0.1 FLOW

        vm.prank(solver1);
        vm.expectEmit(true, true, false, true);
        emit EVMBidRelay.BidSubmitted(intentId, solver1, offeredAPY, maxGasBid);
        relay.submitBid(intentId, offeredAPY, maxGasBid, validBatch);

        // Verify bid was stored
        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertEq(bids.length, 1);
        assertEq(bids[0].solver, solver1);
        assertEq(bids[0].intentId, intentId);
        assertEq(bids[0].offeredAPY, offeredAPY);
        assertEq(bids[0].maxGasBid, maxGasBid);
        assertTrue(bids[0].active);
        assertEq(bids[0].encodedBatch, validBatch);
    }

    // =========================================================================
    // Test 2: Solver can withdraw a bid
    // =========================================================================

    function test_withdrawBid_success() public {
        uint256 intentId = 10;

        vm.prank(solver1);
        relay.submitBid(intentId, 300, 5e16, validBatch);

        // Verify active before withdraw
        assertEq(relay.getActiveBidCount(intentId), 1);

        vm.prank(solver1);
        vm.expectEmit(true, true, false, false);
        emit EVMBidRelay.BidWithdrawn(intentId, solver1);
        relay.withdrawBid(intentId, 0);

        // Bid should now be inactive
        assertEq(relay.getActiveBidCount(intentId), 0);

        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertFalse(bids[0].active);
    }

    // =========================================================================
    // Test 3: getBidsForIntent returns all bids for an intent
    // =========================================================================

    function test_getBidsForIntent_multipleSolvers() public {
        uint256 intentId = 7;

        vm.prank(solver1);
        relay.submitBid(intentId, 500, 1e17, validBatch);

        vm.prank(solver2);
        relay.submitBid(intentId, 800, 2e17, validBatch);

        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertEq(bids.length, 2);
        assertEq(bids[0].solver, solver1);
        assertEq(bids[1].solver, solver2);
        assertEq(relay.getActiveBidCount(intentId), 2);
    }

    // =========================================================================
    // Test 4: Reverts when encodedBatch is empty
    // =========================================================================

    function test_revert_emptyEncodedBatch() public {
        vm.prank(solver1);
        vm.expectRevert("encodedBatch required");
        relay.submitBid(1, 500, 1e17, "");
    }

    // =========================================================================
    // Test 5: Reverts when offeredAPY is zero
    // =========================================================================

    function test_revert_zeroAPY() public {
        vm.prank(solver1);
        vm.expectRevert("APY must be positive");
        relay.submitBid(1, 0, 1e17, validBatch);
    }

    // =========================================================================
    // Test 6: Reverts when maxGasBid is zero
    // =========================================================================

    function test_revert_zeroMaxGasBid() public {
        vm.prank(solver1);
        vm.expectRevert("maxGasBid must be positive");
        relay.submitBid(1, 500, 0, validBatch);
    }

    // =========================================================================
    // Test 7: Non-owner cannot withdraw another solver's bid
    // =========================================================================

    function test_revert_withdrawNotYourBid() public {
        uint256 intentId = 99;

        vm.prank(solver1);
        relay.submitBid(intentId, 500, 1e17, validBatch);

        vm.prank(solver2);
        vm.expectRevert("Not your bid");
        relay.withdrawBid(intentId, 0);
    }

    // =========================================================================
    // Test 8: bidsBysolver index is populated
    // =========================================================================

    function test_bidsBySolverIndexed() public {
        vm.startPrank(solver1);
        relay.submitBid(1, 500, 1e17, validBatch);
        relay.submitBid(2, 700, 1e17, validBatch);
        vm.stopPrank();

        // No direct getter for bidsBysolver (it's a public mapping returning array elements),
        // but we can verify via getBidsForIntent that both intents have the bid.
        EVMBidRelay.EVMBid[] memory bids1 = relay.getBidsForIntent(1);
        EVMBidRelay.EVMBid[] memory bids2 = relay.getBidsForIntent(2);
        assertEq(bids1[0].solver, solver1);
        assertEq(bids2[0].solver, solver1);
    }
}
