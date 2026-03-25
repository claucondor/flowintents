// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {EVMBidRelay} from "../src/EVMBidRelay.sol";

/// @title EVMBidRelayTest
/// @notice Tests for EVMBidRelay — EVM-side intent board and bid board for FlowIntents.
contract EVMBidRelayTest is Test {
    EVMBidRelay public relay;

    address public solver1;
    address public solver2;
    address public creator1;
    address public mockCOA;

    // A minimal valid ABI-encoded StrategyStep[] (one step: raw call to address(1))
    bytes internal validBatch;

    function setUp() public {
        relay = new EVMBidRelay();
        solver1  = makeAddr("solver1");
        solver2  = makeAddr("solver2");
        creator1 = makeAddr("creator1");
        mockCOA  = makeAddr("mockCOA");

        // Build a minimal encodedBatch
        validBatch = abi.encode(
            uint8(3),           // protocol = WFLOW_WRAP
            address(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e), // WFLOW
            abi.encodeWithSelector(bytes4(0xd0e30db0)), // deposit()
            uint256(1 ether)    // value
        );

        // Fund test accounts with FLOW
        vm.deal(creator1, 100 ether);
        vm.deal(mockCOA, 0);
    }

    // =========================================================================
    // submitIntent tests
    // =========================================================================

    function test_submitIntent_yield_success() public {
        uint256 principal = 10 ether;
        uint256 gasEscrow = 0.1 ether;
        uint256 totalValue = principal + gasEscrow;
        uint256 expiryBlock = block.number + 1000;

        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit EVMBidRelay.EVMIntentSubmitted(0, creator1, principal, 0);
        uint256 evmIntentId = relay.submitIntent{value: totalValue}(
            0,           // yield
            500,         // targetAPY: 5%
            0,           // minAmountOut: N/A for yield
            100,         // maxFeeBPS
            30,          // durationDays
            expiryBlock,
            gasEscrow
        );

        assertEq(evmIntentId, 0);
        assertEq(relay.nextEVMIntentId(), 1);

        EVMBidRelay.EVMIntent memory intent = relay.getEVMIntent(0);
        assertEq(intent.creator, creator1);
        assertEq(intent.amount, principal);
        assertEq(intent.intentType, 0);
        assertEq(intent.targetAPY, 500);
        assertEq(intent.gasEscrow, gasEscrow);
        assertFalse(intent.released);
        assertEq(address(relay).balance, totalValue);
    }

    function test_submitIntent_swap_success() public {
        uint256 principal = 5 ether;
        uint256 gasEscrow = 0.05 ether;
        uint256 expiryBlock = block.number + 500;

        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit EVMBidRelay.EVMIntentSubmitted(0, creator1, principal, 1);
        uint256 evmIntentId = relay.submitIntent{value: principal + gasEscrow}(
            1,           // swap
            0,           // targetAPY: N/A
            1000 ether,  // minAmountOut
            50,          // maxFeeBPS
            1,           // durationDays
            expiryBlock,
            gasEscrow
        );

        assertEq(evmIntentId, 0);
        EVMBidRelay.EVMIntent memory intent = relay.getEVMIntent(0);
        assertEq(intent.intentType, 1);
        assertEq(intent.minAmountOut, 1000 ether);
    }

    function test_submitIntent_incrementsId() public {
        uint256 expiryBlock = block.number + 100;

        vm.startPrank(creator1);
        uint256 id0 = relay.submitIntent{value: 2 ether}(0, 500, 0, 100, 30, expiryBlock, 0.1 ether);
        uint256 id1 = relay.submitIntent{value: 2 ether}(0, 600, 0, 100, 30, expiryBlock, 0.1 ether);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(relay.nextEVMIntentId(), 2);
    }

    function test_revert_submitIntent_valueNotExceedGasEscrow() public {
        vm.prank(creator1);
        vm.expectRevert("msg.value must exceed gasEscrow");
        relay.submitIntent{value: 1 ether}(0, 500, 0, 100, 30, block.number + 100, 1 ether);
    }

    function test_revert_submitIntent_expiryBlockInPast() public {
        vm.roll(1000); // set block number to 1000
        vm.prank(creator1);
        vm.expectRevert("expiryBlock must be in the future");
        relay.submitIntent{value: 2 ether}(0, 500, 0, 100, 30, 999, 0.1 ether);
    }

    function test_revert_submitIntent_zeroDurationDays() public {
        vm.prank(creator1);
        vm.expectRevert("durationDays must be positive");
        relay.submitIntent{value: 2 ether}(0, 500, 0, 100, 0, block.number + 100, 0.1 ether);
    }

    function test_revert_submitIntent_yieldWithZeroAPY() public {
        vm.prank(creator1);
        vm.expectRevert("targetAPY must be positive for yield intents");
        relay.submitIntent{value: 2 ether}(0, 0, 0, 100, 30, block.number + 100, 0.1 ether);
    }

    function test_revert_submitIntent_swapWithZeroMinAmountOut() public {
        vm.prank(creator1);
        vm.expectRevert("minAmountOut must be positive for swap intents");
        relay.submitIntent{value: 2 ether}(1, 0, 0, 100, 30, block.number + 100, 0.1 ether);
    }

    function test_revert_submitIntent_invalidIntentType() public {
        vm.prank(creator1);
        vm.expectRevert("invalid intentType");
        relay.submitIntent{value: 2 ether}(2, 500, 0, 100, 30, block.number + 100, 0.1 ether);
    }

    // =========================================================================
    // releaseToCOA tests
    // =========================================================================

    function test_releaseToCOA_success() public {
        uint256 principal = 10 ether;
        uint256 gasEscrow = 0.5 ether;
        uint256 expiryBlock = block.number + 100;

        vm.prank(creator1);
        uint256 evmIntentId = relay.submitIntent{value: principal + gasEscrow}(
            0, 500, 0, 100, 30, expiryBlock, gasEscrow
        );

        uint256 coaBalanceBefore = mockCOA.balance;
        uint256 relayBalanceBefore = address(relay).balance;

        vm.prank(mockCOA);
        vm.expectEmit(true, true, false, true);
        emit EVMBidRelay.EVMIntentReleased(evmIntentId, mockCOA, principal + gasEscrow);
        relay.releaseToCOA(evmIntentId);

        // COA should receive principal + gasEscrow
        assertEq(mockCOA.balance, coaBalanceBefore + principal + gasEscrow);
        // Relay balance should decrease by that amount
        assertEq(address(relay).balance, relayBalanceBefore - (principal + gasEscrow));

        // Intent should be marked released
        EVMBidRelay.EVMIntent memory intent = relay.getEVMIntent(evmIntentId);
        assertTrue(intent.released);
    }

    function test_revert_releaseToCOA_alreadyReleased() public {
        vm.prank(creator1);
        uint256 evmIntentId = relay.submitIntent{value: 2 ether}(
            0, 500, 0, 100, 30, block.number + 100, 0.1 ether
        );

        vm.prank(mockCOA);
        relay.releaseToCOA(evmIntentId);

        // Second call should revert
        vm.prank(mockCOA);
        vm.expectRevert("already released");
        relay.releaseToCOA(evmIntentId);
    }

    function test_revert_releaseToCOA_nonexistent() public {
        vm.prank(mockCOA);
        vm.expectRevert("intent does not exist");
        relay.releaseToCOA(999);
    }

    function test_releaseToCOA_zeroGasEscrow() public {
        // gasEscrow can be 0 (but msg.value must still exceed it, so principal > 0)
        uint256 principal = 5 ether;
        uint256 gasEscrow = 0;
        // msg.value must exceed gasEscrow (strictly > 0)
        vm.prank(creator1);
        uint256 evmIntentId = relay.submitIntent{value: principal + 1}(
            0, 500, 0, 100, 30, block.number + 100, gasEscrow
        );

        vm.prank(mockCOA);
        relay.releaseToCOA(evmIntentId);

        assertEq(mockCOA.balance, principal + 1);
    }

    // =========================================================================
    // submitBid tests (updated for new signature with offeredAmountOut)
    // =========================================================================

    function test_submitBid_yield_success() public {
        uint256 intentId = 42;
        uint256 offeredAPY = 500;   // 5%
        uint256 maxGasBid = 1e17;   // 0.1 FLOW

        vm.prank(solver1);
        vm.expectEmit(true, true, false, true);
        emit EVMBidRelay.BidSubmitted(intentId, solver1, offeredAPY, maxGasBid);
        relay.submitBid(intentId, offeredAPY, 0, maxGasBid, validBatch);

        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertEq(bids.length, 1);
        assertEq(bids[0].solver, solver1);
        assertEq(bids[0].intentId, intentId);
        assertEq(bids[0].offeredAPY, offeredAPY);
        assertEq(bids[0].offeredAmountOut, 0);
        assertEq(bids[0].maxGasBid, maxGasBid);
        assertTrue(bids[0].active);
        assertEq(bids[0].encodedBatch, validBatch);
    }

    function test_submitBid_swap_success() public {
        uint256 intentId = 77;
        uint256 offeredAmountOut = 500 ether;
        uint256 maxGasBid = 2e17;

        vm.prank(solver1);
        relay.submitBid(intentId, 0, offeredAmountOut, maxGasBid, validBatch);

        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertEq(bids.length, 1);
        assertEq(bids[0].offeredAPY, 0);
        assertEq(bids[0].offeredAmountOut, offeredAmountOut);
    }

    function test_withdrawBid_success() public {
        uint256 intentId = 10;

        vm.prank(solver1);
        relay.submitBid(intentId, 300, 0, 5e16, validBatch);

        assertEq(relay.getActiveBidCount(intentId), 1);

        vm.prank(solver1);
        vm.expectEmit(true, true, false, false);
        emit EVMBidRelay.BidWithdrawn(intentId, solver1);
        relay.withdrawBid(intentId, 0);

        assertEq(relay.getActiveBidCount(intentId), 0);
        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertFalse(bids[0].active);
    }

    function test_getBidsForIntent_multipleSolvers() public {
        uint256 intentId = 7;

        vm.prank(solver1);
        relay.submitBid(intentId, 500, 0, 1e17, validBatch);

        vm.prank(solver2);
        relay.submitBid(intentId, 800, 0, 2e17, validBatch);

        EVMBidRelay.EVMBid[] memory bids = relay.getBidsForIntent(intentId);
        assertEq(bids.length, 2);
        assertEq(bids[0].solver, solver1);
        assertEq(bids[1].solver, solver2);
        assertEq(relay.getActiveBidCount(intentId), 2);
    }

    function test_revert_emptyEncodedBatch() public {
        vm.prank(solver1);
        vm.expectRevert("encodedBatch required");
        relay.submitBid(1, 500, 0, 1e17, "");
    }

    function test_revert_noOfferedValue() public {
        vm.prank(solver1);
        vm.expectRevert("must provide offeredAPY or offeredAmountOut");
        relay.submitBid(1, 0, 0, 1e17, validBatch);
    }

    function test_revert_zeroMaxGasBid() public {
        vm.prank(solver1);
        vm.expectRevert("maxGasBid must be positive");
        relay.submitBid(1, 500, 0, 0, validBatch);
    }

    function test_revert_withdrawNotYourBid() public {
        uint256 intentId = 99;

        vm.prank(solver1);
        relay.submitBid(intentId, 500, 0, 1e17, validBatch);

        vm.prank(solver2);
        vm.expectRevert("Not your bid");
        relay.withdrawBid(intentId, 0);
    }

    function test_bidsBySolverIndexed() public {
        vm.startPrank(solver1);
        relay.submitBid(1, 500, 0, 1e17, validBatch);
        relay.submitBid(2, 700, 0, 1e17, validBatch);
        vm.stopPrank();

        EVMBidRelay.EVMBid[] memory bids1 = relay.getBidsForIntent(1);
        EVMBidRelay.EVMBid[] memory bids2 = relay.getBidsForIntent(2);
        assertEq(bids1[0].solver, solver1);
        assertEq(bids2[0].solver, solver1);
    }
}
