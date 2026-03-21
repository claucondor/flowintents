// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AgentReputationRegistry} from "../src/AgentReputationRegistry.sol";
import {IAgentReputationRegistry} from "../src/interfaces/IAgentReputationRegistry.sol";

/// @title AgentReputationRegistry Tests + Invariant Tests
contract AgentReputationRegistryTest is Test {
    AgentReputationRegistry public registry;

    address public owner      = makeAddr("owner");
    address public validation = makeAddr("validationRegistry");
    address public attacker   = makeAddr("attacker");

    uint256 constant INITIAL_SCORE = 100e18;
    uint256 constant SCORE_FLOOR   = 10e18;
    uint256 constant SCORE_CAP     = 1000e18;
    uint256 constant SUCCESS_DELTA = 10e18;
    uint256 constant FAILURE_DELTA = 20e18;

    function setUp() public {
        vm.prank(owner);
        registry = new AgentReputationRegistry(owner, validation);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitialScore_IsDefault() public view {
        assertEq(registry.getScore(1), INITIAL_SCORE);
    }

    function test_InitialMultiplier_IsOne() public view {
        // score=100e18, multiplier = 100e18/100e18 * 1e18 = 1e18
        assertEq(registry.getMultiplier(1), 1e18);
    }

    function test_InitialHistory_IsZero() public view {
        (uint256 c, uint256 f) = registry.getHistory(1);
        assertEq(c, 0);
        assertEq(f, 0);
    }

    // -------------------------------------------------------------------------
    // Access control
    // -------------------------------------------------------------------------

    function test_OnlyValidationRegistry_CanRecord() public {
        vm.prank(attacker);
        vm.expectRevert("AgentReputationRegistry: caller is not validation registry");
        registry.recordCompletion(1, 1, true);
    }

    function test_ValidationRegistry_CanRecord() public {
        vm.prank(validation);
        registry.recordCompletion(1, 1, true);
        assertEq(registry.getScore(1), INITIAL_SCORE + SUCCESS_DELTA);
    }

    // -------------------------------------------------------------------------
    // Score mechanics
    // -------------------------------------------------------------------------

    function test_Success_IncreasesScore() public {
        vm.prank(validation);
        registry.recordCompletion(1, 1, true);
        assertEq(registry.getScore(1), INITIAL_SCORE + SUCCESS_DELTA);
    }

    function test_Failure_DecreasesScore() public {
        vm.prank(validation);
        registry.recordCompletion(1, 1, false);
        assertEq(registry.getScore(1), INITIAL_SCORE - FAILURE_DELTA);
    }

    function test_Score_CapAt1000e18() public {
        // Need (1000e18 - 100e18) / 10e18 = 90 successes to cap
        vm.startPrank(validation);
        for (uint256 i = 0; i < 100; i++) {
            registry.recordCompletion(1, i, true);
        }
        vm.stopPrank();
        assertEq(registry.getScore(1), SCORE_CAP);
    }

    function test_Score_FloorAt10e18() public {
        // Need enough failures to hit floor
        vm.startPrank(validation);
        for (uint256 i = 0; i < 50; i++) {
            registry.recordCompletion(1, i, false);
        }
        vm.stopPrank();
        assertEq(registry.getScore(1), SCORE_FLOOR);
    }

    function test_History_TrackedCorrectly() public {
        vm.startPrank(validation);
        registry.recordCompletion(1, 1, true);
        registry.recordCompletion(1, 2, true);
        registry.recordCompletion(1, 3, false);
        vm.stopPrank();

        (uint256 c, uint256 f) = registry.getHistory(1);
        assertEq(c, 2);
        assertEq(f, 1);
    }

    function test_Multiplier_DoubleAt200e18() public {
        // Get to 200e18: need 10 successes from 100e18
        vm.startPrank(validation);
        for (uint256 i = 0; i < 10; i++) {
            registry.recordCompletion(1, i, true);
        }
        vm.stopPrank();
        assertEq(registry.getScore(1), 200e18);
        // multiplier = 200e18 / 100e18 * 1e18 = 2e18
        assertEq(registry.getMultiplier(1), 2e18);
    }

    function test_CompletionRecorded_Event() public {
        vm.expectEmit(true, true, false, true);
        emit IAgentReputationRegistry.CompletionRecorded(1, 42, true, INITIAL_SCORE + SUCCESS_DELTA);

        vm.prank(validation);
        registry.recordCompletion(1, 42, true);
    }

    // -------------------------------------------------------------------------
    // Fuzz Tests
    // -------------------------------------------------------------------------

    function testFuzz_Score_NeverExceedsCap(uint8 successes) public {
        vm.startPrank(validation);
        for (uint256 i = 0; i < successes; i++) {
            registry.recordCompletion(1, i, true);
        }
        vm.stopPrank();
        assertLe(registry.getScore(1), SCORE_CAP);
    }

    function testFuzz_Score_NeverBelowFloor(uint8 failures) public {
        vm.startPrank(validation);
        for (uint256 i = 0; i < failures; i++) {
            registry.recordCompletion(1, i, false);
        }
        vm.stopPrank();
        assertGe(registry.getScore(1), SCORE_FLOOR);
    }

    function testFuzz_MixedOperations_ScoreInBounds(uint8 successes, uint8 failures) public {
        vm.startPrank(validation);
        uint256 total = uint256(successes) + uint256(failures);
        for (uint256 i = 0; i < total; i++) {
            bool isSuccess = i < successes;
            registry.recordCompletion(1, i, isSuccess);
        }
        vm.stopPrank();

        uint256 score = registry.getScore(1);
        assertGe(score, SCORE_FLOOR, "Score below floor");
        assertLe(score, SCORE_CAP,   "Score above cap");
    }
}

// -------------------------------------------------------------------------
// Invariant Handler + Test
// -------------------------------------------------------------------------

/// @notice Stateful handler used by the invariant test
contract ReputationHandler is Test {
    AgentReputationRegistry public registry;
    address public validation;

    constructor(AgentReputationRegistry _registry, address _validation) {
        registry = _registry;
        validation = _validation;
    }

    function recordSuccess(uint256 tokenId, uint256 intentId) external {
        tokenId = bound(tokenId, 1, 5);
        intentId = bound(intentId, 1, 1000);
        vm.prank(validation);
        registry.recordCompletion(tokenId, intentId, true);
    }

    function recordFailure(uint256 tokenId, uint256 intentId) external {
        tokenId = bound(tokenId, 1, 5);
        intentId = bound(intentId, 1, 1000);
        vm.prank(validation);
        registry.recordCompletion(tokenId, intentId, false);
    }
}

contract AgentReputationInvariantTest is Test {
    AgentReputationRegistry public registry;
    ReputationHandler public handler;

    address public owner      = makeAddr("owner");
    address public validation = makeAddr("validationRegistry");

    uint256 constant SCORE_FLOOR = 10e18;
    uint256 constant SCORE_CAP   = 1000e18;

    function setUp() public {
        vm.prank(owner);
        registry = new AgentReputationRegistry(owner, validation);
        handler  = new ReputationHandler(registry, validation);

        targetContract(address(handler));
    }

    /// @notice Score for any agent must always be in [10e18, 1000e18]
    function invariant_ScoreAlwaysInBounds() public view {
        for (uint256 i = 1; i <= 5; i++) {
            uint256 score = registry.getScore(i);
            assertGe(score, SCORE_FLOOR, "Score below floor");
            assertLe(score, SCORE_CAP,   "Score above cap");
        }
    }

    /// @notice Multiplier should always be >= 0.1e18 (floor/base) and <= 10e18 (cap/base)
    ///         floor score=10e18 → mult = 10e18 * 1e18 / 100e18 = 1e17 (0.1e18)
    ///         cap  score=1000e18 → mult = 1000e18 * 1e18 / 100e18 = 10e18
    function invariant_MultiplierInBounds() public view {
        for (uint256 i = 1; i <= 5; i++) {
            uint256 mult = registry.getMultiplier(i);
            assertGe(mult, 1e17,  "Multiplier below minimum (0.1e18)");
            assertLe(mult, 10e18, "Multiplier above maximum (10e18)");
        }
    }
}
