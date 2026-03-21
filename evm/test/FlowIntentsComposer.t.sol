// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FlowIntentsComposer} from "../src/FlowIntentsComposer.sol";
import {IFlowIntentsComposer} from "../src/interfaces/IFlowIntentsComposer.sol";

/// @title FlowIntentsComposer Tests
/// @notice Unit, fuzz, and COA whitelist tests for the batch executor
contract FlowIntentsComposerTest is Test {
    FlowIntentsComposer public composer;

    address public owner = makeAddr("owner");
    address public coa1  = address(0x0000000000000000000000020000000000000001);
    address public coa2  = address(0x0000000000000000000000020000000000000002);
    address public nonCOA = makeAddr("nonCOA");

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        vm.prank(owner);
        composer = new FlowIntentsComposer(owner);

        // Register coa1
        vm.prank(owner);
        composer.registerCOA(coa1);
    }

    // -------------------------------------------------------------------------
    // COA Whitelist Tests
    // -------------------------------------------------------------------------

    function test_RegisterCOA() public {
        assertEq(composer.coaAddresses(coa1), true);
        assertEq(composer.coaAddresses(coa2), false);
    }

    function test_NonCOACaller_Reverts() public {
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](1);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: address(0x1),
            callData: "",
            value: 0,
            required: false
        });

        vm.prank(nonCOA);
        vm.expectRevert("FlowIntentsComposer: caller is not a registered COA");
        composer.executeBatch(1, steps, nonCOA);
    }

    function test_RegisteredCOA_CanExecute() public {
        // Deploy a simple echo target
        address target = address(new EchoTarget());
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](1);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: target,
            callData: abi.encodeWithSignature("ping()"),
            value: 0,
            required: true
        });

        vm.prank(coa1);
        bool ok = composer.executeBatch(1, steps, coa1);
        assertTrue(ok);
    }

    function test_DeregisterCOA_Reverts() public {
        vm.prank(owner);
        composer.deregisterCOA(coa1);

        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](1);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: address(0x1),
            callData: "",
            value: 0,
            required: false
        });

        vm.prank(coa1);
        vm.expectRevert("FlowIntentsComposer: caller is not a registered COA");
        composer.executeBatch(1, steps, coa1);
    }

    function test_OnlyOwner_CanRegisterCOA() public {
        vm.prank(nonCOA);
        vm.expectRevert();
        composer.registerCOA(coa2);
    }

    function test_EmptyBatch_Reverts() public {
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](0);
        vm.prank(coa1);
        vm.expectRevert("FlowIntentsComposer: empty batch");
        composer.executeBatch(1, steps, coa1);
    }

    // -------------------------------------------------------------------------
    // Required Step Revert Tests
    // -------------------------------------------------------------------------

    function test_RequiredStep_Failure_RevertsAll() public {
        address failTarget = address(new RevertTarget());
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](2);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: failTarget,
            callData: abi.encodeWithSignature("fail()"),
            value: 0,
            required: true  // required = true → should revert
        });
        steps[1] = IFlowIntentsComposer.BatchStep({
            target: address(new EchoTarget()),
            callData: abi.encodeWithSignature("ping()"),
            value: 0,
            required: true
        });

        vm.prank(coa1);
        vm.expectRevert("FlowIntentsComposer: required step failed");
        composer.executeBatch(1, steps, coa1);
    }

    function test_OptionalStep_Failure_ContinuesBatch() public {
        address failTarget = address(new RevertTarget());
        address okTarget   = address(new EchoTarget());

        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](2);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: failTarget,
            callData: abi.encodeWithSignature("fail()"),
            value: 0,
            required: false  // optional → continue on failure
        });
        steps[1] = IFlowIntentsComposer.BatchStep({
            target: okTarget,
            callData: abi.encodeWithSignature("ping()"),
            value: 0,
            required: true
        });

        vm.prank(coa1);
        bool ok = composer.executeBatch(1, steps, coa1);
        assertTrue(ok);
    }

    // -------------------------------------------------------------------------
    // Event Tests
    // -------------------------------------------------------------------------

    function test_BatchExecuted_Event_Emitted() public {
        address target = address(new EchoTarget());
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](1);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: target,
            callData: abi.encodeWithSignature("ping()"),
            value: 0,
            required: true
        });

        vm.expectEmit(true, true, false, true);
        emit IFlowIntentsComposer.BatchExecuted(42, coa1, 1, false);

        vm.prank(coa1);
        composer.executeBatch(42, steps, coa1);
    }

    function test_StepExecuted_Event_Emitted() public {
        address target = address(new EchoTarget());
        IFlowIntentsComposer.BatchStep[] memory steps = new IFlowIntentsComposer.BatchStep[](1);
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: target,
            callData: abi.encodeWithSignature("ping()"),
            value: 0,
            required: true
        });

        vm.expectEmit(true, false, false, true);
        emit IFlowIntentsComposer.StepExecuted(42, 0, target, true);

        vm.prank(coa1);
        composer.executeBatch(42, steps, coa1);
    }

    // -------------------------------------------------------------------------
    // Fuzz Tests
    // -------------------------------------------------------------------------

    /// @notice Fuzz: executeBatch with random steps should never succeed for non-COA
    function testFuzz_NonCOA_AlwaysReverts(
        uint256 intentId,
        address solver,
        uint8 stepCount
    ) public {
        stepCount = uint8(bound(stepCount, 1, 10));

        IFlowIntentsComposer.BatchStep[] memory steps =
            new IFlowIntentsComposer.BatchStep[](stepCount);
        for (uint256 i = 0; i < stepCount; i++) {
            steps[i] = IFlowIntentsComposer.BatchStep({
                target: address(0x1),
                callData: "",
                value: 0,
                required: false
            });
        }

        // Ensure the random solver is not a registered COA
        vm.assume(solver != coa1 && solver != owner);
        vm.prank(solver);
        vm.expectRevert("FlowIntentsComposer: caller is not a registered COA");
        composer.executeBatch(intentId, steps, solver);
    }

    /// @notice Fuzz: multiple optional steps — batch should always complete even if some fail
    function testFuzz_OptionalSteps_NeverRevert(
        uint256 intentId,
        uint8 stepCount
    ) public {
        stepCount = uint8(bound(stepCount, 1, 20));

        IFlowIntentsComposer.BatchStep[] memory steps =
            new IFlowIntentsComposer.BatchStep[](stepCount);

        // Mix of echo (success) and revert (fail) targets, all optional
        address echoTarget   = address(new EchoTarget());
        address revertTarget = address(new RevertTarget());

        for (uint256 i = 0; i < stepCount; i++) {
            address tgt = (i % 2 == 0) ? echoTarget : revertTarget;
            steps[i] = IFlowIntentsComposer.BatchStep({
                target: tgt,
                callData: (i % 2 == 0)
                    ? abi.encodeWithSignature("ping()")
                    : abi.encodeWithSignature("fail()"),
                value: 0,
                required: false
            });
        }

        vm.prank(coa1);
        bool ok = composer.executeBatch(intentId, steps, coa1);
        assertTrue(ok);
    }

    /// @notice Fuzz: required step at index 0 that always fails → always reverts
    function testFuzz_RequiredFailingStep_AlwaysReverts(uint256 intentId, uint8 extraSteps) public {
        extraSteps = uint8(bound(extraSteps, 0, 9));
        uint256 len = 1 + uint256(extraSteps);

        IFlowIntentsComposer.BatchStep[] memory steps =
            new IFlowIntentsComposer.BatchStep[](len);

        // First step: required + always reverts
        steps[0] = IFlowIntentsComposer.BatchStep({
            target: address(new RevertTarget()),
            callData: abi.encodeWithSignature("fail()"),
            value: 0,
            required: true
        });

        // Fill remaining with optional successful steps
        address echo = address(new EchoTarget());
        for (uint256 i = 1; i < len; i++) {
            steps[i] = IFlowIntentsComposer.BatchStep({
                target: echo,
                callData: abi.encodeWithSignature("ping()"),
                value: 0,
                required: false
            });
        }

        vm.prank(coa1);
        vm.expectRevert("FlowIntentsComposer: required step failed");
        composer.executeBatch(intentId, steps, coa1);
    }
}

// -------------------------------------------------------------------------
// Helper Contracts
// -------------------------------------------------------------------------

/// @dev Simple contract that succeeds on ping()
contract EchoTarget {
    uint256 public callCount;
    function ping() external returns (bool) {
        callCount++;
        return true;
    }
    receive() external payable {}
}

/// @dev Simple contract that always reverts
contract RevertTarget {
    function fail() external pure {
        revert("RevertTarget: intentional failure");
    }
}
