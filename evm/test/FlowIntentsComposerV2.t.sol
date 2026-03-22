// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FlowIntentsComposerV2, ILayerZeroEndpoint} from "../src/FlowIntentsComposerV2.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";

/// @title FlowIntentsComposerV2Test
/// @notice Comprehensive tests for the dual-chain FlowIntentsComposerV2 contract
contract FlowIntentsComposerV2Test is Test {
    FlowIntentsComposerV2 public composer;
    AgentIdentityRegistry public identityReg;

    address public owner;
    address public user1;
    address public user2;
    address public mockCOA;

    // Mock addresses for protocol tests
    address public mockMOREPool;
    address public mockLZEndpoint;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockCOA = makeAddr("mockCOA");
        mockMOREPool = makeAddr("mockMOREPool");
        mockLZEndpoint = makeAddr("mockLZEndpoint");

        // Deploy identity registry
        identityReg = new AgentIdentityRegistry(owner);

        // Deploy ComposerV2
        composer = new FlowIntentsComposerV2(owner, address(identityReg));

        // Set authorized COA
        composer.setAuthorizedCOA(mockCOA);

        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(mockCOA, 100 ether);
        vm.deal(address(composer), 10 ether);
    }

    // =========================================================================
    // Test 1: EVM user submits intent with native FLOW
    // =========================================================================

    function test_submitIntent_nativeFLOW() public {
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 10 ether}(
            address(0),     // native FLOW
            0,              // amount ignored for native
            500,            // 5% APY
            30,             // 30 days
            0               // EVM_YIELD
        );

        assertEq(intentId, 1, "First intent should have ID 1");

        // Verify stored data
        FlowIntentsComposerV2.EVMIntentRequest memory req = composer.getIntentRequest(intentId);

        assertEq(req.id, 1);
        assertEq(req.user, user1);
        assertEq(req.token, address(0));
        assertEq(req.amount, 10 ether);
        assertEq(req.targetAPY, 500);
        assertEq(req.durationDays, 30);
        assertEq(req.principalSide, 0); // EVM_YIELD
        assertGt(req.submittedAt, 0);
        assertFalse(req.pickedUp);

        // Verify balance tracked
        assertEq(composer.intentBalances(intentId), 10 ether);
        assertEq(composer.getIntentBalance(intentId), 10 ether);
    }

    function test_submitIntent_revert_zeroAPY() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: zero APY");
        composer.submitIntent{value: 1 ether}(address(0), 0, 0, 30, 0);
    }

    function test_submitIntent_revert_zeroDuration() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: zero duration");
        composer.submitIntent{value: 1 ether}(address(0), 0, 500, 0, 0);
    }

    function test_submitIntent_revert_noFLOW() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: no FLOW sent");
        composer.submitIntent(address(0), 0, 500, 30, 0);
    }

    function test_submitIntent_multipleIntents() public {
        vm.startPrank(user1);

        uint256 id1 = composer.submitIntent{value: 5 ether}(address(0), 0, 500, 30, 0);
        uint256 id2 = composer.submitIntent{value: 3 ether}(address(0), 0, 800, 60, 1);

        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(composer.nextIntentId(), 3);
    }

    // =========================================================================
    // Test 2: getPendingIntents() returns the submitted intent
    // =========================================================================

    function test_getPendingIntents_returnsSubmitted() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(user2);
        composer.submitIntent{value: 5 ether}(address(0), 0, 800, 60, 1);

        (uint256[] memory ids, FlowIntentsComposerV2.EVMIntentRequest[] memory requests) =
            composer.getPendingIntents();

        assertEq(ids.length, 2, "Should have 2 pending intents");
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(requests[0].user, user1);
        assertEq(requests[1].user, user2);
        assertEq(requests[0].amount, 10 ether);
        assertEq(requests[1].amount, 5 ether);
    }

    function test_getPendingIntents_empty() public view {
        (uint256[] memory ids, ) = composer.getPendingIntents();
        assertEq(ids.length, 0, "Should have no pending intents");
    }

    function test_getPendingIntents_excludesPickedUp() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(user1);
        composer.submitIntent{value: 5 ether}(address(0), 0, 800, 60, 0);

        // Pick up first intent
        vm.prank(mockCOA);
        composer.markPickedUp(1);

        (uint256[] memory ids, ) = composer.getPendingIntents();
        assertEq(ids.length, 1, "Should have 1 pending intent after pickup");
        assertEq(ids[0], 2);
    }

    // =========================================================================
    // Test 3: COA calls markPickedUp()
    // =========================================================================

    function test_markPickedUp_byCOA() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        FlowIntentsComposerV2.EVMIntentRequest memory req = composer.getIntentRequest(1);
        assertTrue(req.pickedUp, "Intent should be marked as picked up");

        // Status should be PICKED_UP (1)
        FlowIntentsComposerV2.IntentStatus status = composer.getIntentStatus(1);
        assertEq(uint8(status), 1); // PICKED_UP
    }

    function test_markPickedUp_revert_notCOA() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: not COA");
        composer.markPickedUp(1);
    }

    function test_markPickedUp_revert_alreadyPickedUp() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        vm.prank(mockCOA);
        vm.expectRevert("FlowIntentsComposerV2: already picked up");
        composer.markPickedUp(1);
    }

    // =========================================================================
    // Test 4: Execute strategy — MORE Protocol deposit (mock)
    // =========================================================================

    function test_executeStrategy_MOREDeposit() public {
        // Setup: submit and pick up intent
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mock the MORE pool to accept calls
        // Simulate a deposit call that succeeds
        vm.mockCall(
            mockMOREPool,
            abi.encodeWithSignature("deposit()"),
            abi.encode(true)
        );

        // Build strategy steps
        FlowIntentsComposerV2.StrategyStep[] memory steps = new FlowIntentsComposerV2.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV2.StrategyStep({
            protocol: 0, // MORE
            target: mockMOREPool,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(mockCOA);
        bool success = composer.executeStrategy(1, encodedBatch);
        assertTrue(success, "Strategy execution should succeed");

        // Status should be EXECUTING (2)
        FlowIntentsComposerV2.IntentStatus status = composer.getIntentStatus(1);
        assertEq(uint8(status), 2);
    }

    function test_executeStrategy_revert_stepFails() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mock the target to revert
        vm.mockCallRevert(
            mockMOREPool,
            abi.encodeWithSignature("deposit()"),
            "MORE: insufficient collateral"
        );

        FlowIntentsComposerV2.StrategyStep[] memory steps = new FlowIntentsComposerV2.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV2.StrategyStep({
            protocol: 0,
            target: mockMOREPool,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(mockCOA);
        vm.expectRevert("FlowIntentsComposerV2: strategy step failed");
        composer.executeStrategy(1, encodedBatch);
    }

    function test_executeStrategy_multipleSteps() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mock WFLOW wrap + MORE deposit
        address mockWFLOW = makeAddr("mockWFLOW");
        vm.mockCall(mockWFLOW, abi.encodeWithSignature("deposit()"), abi.encode(true));
        vm.mockCall(mockMOREPool, abi.encodeWithSignature("supply(address,uint256)"), abi.encode(true));

        FlowIntentsComposerV2.StrategyStep[] memory steps = new FlowIntentsComposerV2.StrategyStep[](2);
        steps[0] = FlowIntentsComposerV2.StrategyStep({
            protocol: 3, // WFLOW_WRAP
            target: mockWFLOW,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });
        steps[1] = FlowIntentsComposerV2.StrategyStep({
            protocol: 0, // MORE
            target: mockMOREPool,
            callData: abi.encodeWithSignature("supply(address,uint256)"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(mockCOA);
        bool success = composer.executeStrategy(1, encodedBatch);
        assertTrue(success, "Multi-step strategy should succeed");
    }

    // =========================================================================
    // Test 5: Execute strategy — LayerZero bridge (mock)
    // =========================================================================

    function test_executeStrategy_layerZeroBridge() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mock the LZ endpoint send call
        address lzEndpoint = composer.LAYERZERO_ENDPOINT();
        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "send(uint32,bytes32,bytes,bytes,address)"
            ),
            abi.encode()
        );

        // Build a strategy with LZ bridge step
        bytes memory lzCallData = abi.encodeWithSignature(
            "send(uint32,bytes32,bytes,bytes,address)",
            uint32(30101), // Ethereum endpoint ID
            bytes32(uint256(uint160(user1))), // receiver
            bytes(""), // message
            bytes(""), // options
            address(composer) // refund
        );

        FlowIntentsComposerV2.StrategyStep[] memory steps = new FlowIntentsComposerV2.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV2.StrategyStep({
            protocol: 2, // LAYERZERO
            target: lzEndpoint,
            callData: lzCallData,
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(mockCOA);
        bool success = composer.executeStrategy(1, encodedBatch);
        assertTrue(success, "LZ bridge strategy should succeed");
    }

    // =========================================================================
    // Test 6: User withdraw() after completion
    // =========================================================================

    function test_withdraw_afterCompletion() public {
        // Submit intent
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        // Pick up
        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mark completed with yield (11 ether = 10 principal + 1 yield)
        // First, ensure composer has enough balance
        vm.deal(address(composer), 20 ether);

        vm.prank(mockCOA);
        composer.markCompleted(1, 11 ether);

        // Verify status
        FlowIntentsComposerV2.IntentStatus status = composer.getIntentStatus(1);
        assertEq(uint8(status), 3); // COMPLETED

        // Withdraw
        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(1);
        uint256 balAfter = user1.balance;

        assertEq(balAfter - balBefore, 11 ether, "Should receive principal + yield");
        assertEq(composer.intentBalances(1), 0, "Balance should be zero after withdrawal");
    }

    function test_withdraw_afterCancellation() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(user1);
        composer.cancelIntent(1);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(1);
        uint256 balAfter = user1.balance;

        assertEq(balAfter - balBefore, 10 ether, "Should get full principal back");
    }

    function test_withdraw_revert_notOwner() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        vm.deal(address(composer), 20 ether);
        vm.prank(mockCOA);
        composer.markCompleted(1, 10 ether);

        vm.prank(user2);
        vm.expectRevert("FlowIntentsComposerV2: not intent owner");
        composer.withdraw(1);
    }

    function test_withdraw_revert_notWithdrawable() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        // Still PENDING — cannot withdraw
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: not withdrawable");
        composer.withdraw(1);
    }

    // =========================================================================
    // Additional edge case tests
    // =========================================================================

    function test_cancelIntent_onlyPending() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        // Pick up first
        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Try to cancel — should fail
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: not pending");
        composer.cancelIntent(1);
    }

    function test_setAuthorizedCOA_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        composer.setAuthorizedCOA(user1);
    }

    function test_executeStrategy_revert_notCOA() public {
        vm.prank(user1);
        composer.submitIntent{value: 10 ether}(address(0), 0, 500, 30, 0);

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        FlowIntentsComposerV2.StrategyStep[] memory steps = new FlowIntentsComposerV2.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV2.StrategyStep({
            protocol: 4,
            target: mockMOREPool,
            callData: "",
            value: 0
        });
        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV2: not COA");
        composer.executeStrategy(1, encodedBatch);
    }

    function test_constants() public view {
        assertEq(
            composer.LAYERZERO_ENDPOINT(),
            0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa,
            "LayerZero endpoint should match known Flow EVM address"
        );
    }
}
