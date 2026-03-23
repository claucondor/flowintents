// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FlowIntentsComposerV3} from "../src/FlowIntentsComposerV3.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal ERC20 mock for swap intent tests
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title FlowIntentsComposerV3Test
/// @notice Tests for V3 — covers swap intents plus V2 yield regression
contract FlowIntentsComposerV3Test is Test {
    FlowIntentsComposerV3 public composer;
    AgentIdentityRegistry public identityReg;

    MockERC20 public tokenA; // used as tokenIn for ERC20 swap tests
    MockERC20 public tokenB; // used as tokenOut for ERC20 swap tests

    address public owner;
    address public user1;
    address public user2;
    address public mockCOA;
    address public mockMOREPool;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockCOA = makeAddr("mockCOA");
        mockMOREPool = makeAddr("mockMOREPool");

        // Deploy identity registry
        identityReg = new AgentIdentityRegistry(owner);

        // Deploy V3
        composer = new FlowIntentsComposerV3(owner, address(identityReg));
        composer.setAuthorizedCOA(mockCOA);

        // Deploy mock tokens
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");

        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(mockCOA, 100 ether);
        vm.deal(address(composer), 10 ether);

        // Mint ERC20s for users
        tokenA.mint(user1, 1000 ether);
        tokenA.mint(user2, 1000 ether);
        tokenB.mint(address(composer), 1000 ether); // solver deposits tokenB back
    }

    // =========================================================================
    // test_submitSwapIntent_nativeFlow
    // =========================================================================

    function test_submitSwapIntent_nativeFlow() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),         // tokenIn = native FLOW
            0,                  // amount ignored for native
            address(tokenB),    // tokenOut = tokenB
            100 ether,          // minAmountOut
            7                   // 7 days
        );

        assertEq(intentId, 1, "First intent should have ID 1");

        FlowIntentsComposerV3.EVMIntentRequest memory req = composer.getIntentRequest(intentId);

        assertEq(req.id, 1);
        assertEq(req.user, user1);
        assertEq(req.token, address(0));
        assertEq(req.amount, 5 ether);
        assertEq(req.tokenOut, address(tokenB));
        assertEq(req.minAmountOut, 100 ether);
        assertEq(req.durationDays, 7);
        assertEq(uint8(req.intentType), uint8(FlowIntentsComposerV3.IntentType.SWAP));
        assertFalse(req.pickedUp);

        // Balance tracked
        assertEq(composer.getIntentBalance(intentId), 5 ether);

        // Status is PENDING
        assertEq(
            uint8(composer.getIntentStatus(intentId)),
            uint8(FlowIntentsComposerV3.IntentStatus.PENDING)
        );
    }

    // =========================================================================
    // test_submitSwapIntent_erc20
    // =========================================================================

    function test_submitSwapIntent_erc20() public {
        uint256 depositAmount = 200 ether;

        vm.startPrank(user1);
        tokenA.approve(address(composer), depositAmount);
        uint256 intentId = composer.submitSwapIntent(
            address(tokenA),    // tokenIn = tokenA
            depositAmount,
            address(tokenB),    // tokenOut = tokenB
            50 ether,           // minAmountOut
            14                  // 14 days
        );
        vm.stopPrank();

        assertEq(intentId, 1);

        FlowIntentsComposerV3.EVMIntentRequest memory req = composer.getIntentRequest(intentId);

        assertEq(req.token, address(tokenA));
        assertEq(req.amount, depositAmount);
        assertEq(req.tokenOut, address(tokenB));
        assertEq(req.minAmountOut, 50 ether);
        assertEq(uint8(req.intentType), uint8(FlowIntentsComposerV3.IntentType.SWAP));

        // Tokens transferred to contract
        assertEq(tokenA.balanceOf(address(composer)), depositAmount);
        assertEq(composer.getIntentBalance(intentId), depositAmount);
    }

    // =========================================================================
    // test_submitSwapIntent_revert_zeroMinAmount
    // =========================================================================

    function test_submitSwapIntent_revert_zeroMinAmount() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV3: zero minAmountOut");
        composer.submitSwapIntent{value: 1 ether}(
            address(0),
            0,
            address(tokenB),
            0,      // minAmountOut = 0 — should revert
            7
        );
    }

    // =========================================================================
    // test_submitSwapIntent_revert_zeroDuration
    // =========================================================================

    function test_submitSwapIntent_revert_zeroDuration() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV3: zero duration");
        composer.submitSwapIntent{value: 1 ether}(
            address(0),
            0,
            address(tokenB),
            100 ether,
            0       // durationDays = 0 — should revert
        );
    }

    // =========================================================================
    // test_submitSwapIntent_revert_sameToken
    // =========================================================================

    function test_submitSwapIntent_revert_sameToken() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV3: same token");
        composer.submitSwapIntent{value: 1 ether}(
            address(0),     // tokenIn = native FLOW
            0,
            address(0),     // tokenOut = native FLOW — same as tokenIn, should revert
            100 ether,
            7
        );
    }

    // =========================================================================
    // test_submitSwapIntent_revert_noFlowSent
    // =========================================================================

    function test_submitSwapIntent_revert_noFlowSent() public {
        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV3: no FLOW sent");
        // tokenIn = address(0) but no msg.value
        composer.submitSwapIntent(
            address(0),
            0,
            address(tokenB),
            100 ether,
            7
        );
    }

    // =========================================================================
    // test_submitYieldIntent_stillWorks — V2 regression
    // =========================================================================

    function test_submitYieldIntent_stillWorks() public {
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 10 ether}(
            address(0),     // native FLOW
            0,
            500,            // 5% APY
            30,             // 30 days
            0               // EVM_YIELD
        );

        assertEq(intentId, 1);

        FlowIntentsComposerV3.EVMIntentRequest memory req = composer.getIntentRequest(intentId);

        assertEq(req.token, address(0));
        assertEq(req.amount, 10 ether);
        assertEq(req.targetAPY, 500);
        assertEq(req.durationDays, 30);
        assertEq(uint8(req.intentType), uint8(FlowIntentsComposerV3.IntentType.YIELD));
        assertEq(req.tokenOut, address(0));
        assertEq(req.minAmountOut, 0);

        assertEq(composer.getIntentBalance(intentId), 10 ether);
        assertEq(
            uint8(composer.getIntentStatus(intentId)),
            uint8(FlowIntentsComposerV3.IntentStatus.PENDING)
        );
    }

    // =========================================================================
    // test_getPendingIntents_includesSwapAndYield
    // =========================================================================

    function test_getPendingIntents_includesSwapAndYield() public {
        // Submit a yield intent
        vm.prank(user1);
        composer.submitIntent{value: 5 ether}(address(0), 0, 500, 30, 0);

        // Submit a swap intent
        vm.prank(user2);
        composer.submitSwapIntent{value: 3 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        (uint256[] memory ids, FlowIntentsComposerV3.EVMIntentRequest[] memory requests) =
            composer.getPendingIntents();

        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(uint8(requests[0].intentType), uint8(FlowIntentsComposerV3.IntentType.YIELD));
        assertEq(uint8(requests[1].intentType), uint8(FlowIntentsComposerV3.IntentType.SWAP));
    }

    // =========================================================================
    // test_markPickedUp_swapIntent
    // =========================================================================

    function test_markPickedUp_swapIntent() public {
        vm.prank(user1);
        composer.submitSwapIntent{value: 5 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        FlowIntentsComposerV3.EVMIntentRequest memory req = composer.getIntentRequest(1);
        assertTrue(req.pickedUp);
        assertEq(
            uint8(composer.getIntentStatus(1)),
            uint8(FlowIntentsComposerV3.IntentStatus.PICKED_UP)
        );
    }

    // =========================================================================
    // test_executeStrategy_swapIntent
    // =========================================================================

    function test_executeStrategy_swapIntent() public {
        vm.prank(user1);
        composer.submitSwapIntent{value: 5 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        vm.prank(mockCOA);
        composer.markPickedUp(1);

        // Mock a swap target
        address mockSwapRouter = makeAddr("mockSwapRouter");
        vm.mockCall(
            mockSwapRouter,
            abi.encodeWithSignature("swap()"),
            abi.encode(true)
        );

        FlowIntentsComposerV3.StrategyStep[] memory steps = new FlowIntentsComposerV3.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV3.StrategyStep({
            protocol: 4, // CUSTOM
            target: mockSwapRouter,
            callData: abi.encodeWithSignature("swap()"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.prank(mockCOA);
        bool success = composer.executeStrategy(1, encodedBatch);
        assertTrue(success);

        assertEq(
            uint8(composer.getIntentStatus(1)),
            uint8(FlowIntentsComposerV3.IntentStatus.EXECUTING)
        );
    }

    // =========================================================================
    // test_cancelSwapIntent_refundsTokenIn
    // =========================================================================

    function test_cancelSwapIntent_nativeFlow_refund() public {
        vm.prank(user1);
        composer.submitSwapIntent{value: 5 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        // Cancel before pickup
        vm.prank(user1);
        composer.cancelIntent(1);

        assertEq(
            uint8(composer.getIntentStatus(1)),
            uint8(FlowIntentsComposerV3.IntentStatus.CANCELLED)
        );

        // Withdraw refund
        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(1);
        uint256 balAfter = user1.balance;

        assertEq(balAfter - balBefore, 5 ether, "Should receive full tokenIn back on cancel");
    }

    // =========================================================================
    // test_yieldIntent_fullLifecycle — regression
    // =========================================================================

    function test_yieldIntent_fullLifecycle() public {
        // Submit
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 10 ether}(
            address(0), 0, 500, 30, 0
        );

        // Pick up
        vm.prank(mockCOA);
        composer.markPickedUp(intentId);

        // Execute strategy (mocked)
        vm.mockCall(
            mockMOREPool,
            abi.encodeWithSignature("deposit()"),
            abi.encode(true)
        );

        FlowIntentsComposerV3.StrategyStep[] memory steps = new FlowIntentsComposerV3.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV3.StrategyStep({
            protocol: 0,
            target: mockMOREPool,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });

        vm.prank(mockCOA);
        composer.executeStrategy(intentId, abi.encode(steps));

        // Mark completed with yield
        vm.deal(address(composer), 20 ether);
        vm.prank(mockCOA);
        composer.markCompleted(intentId, 11 ether);

        assertEq(
            uint8(composer.getIntentStatus(intentId)),
            uint8(FlowIntentsComposerV3.IntentStatus.COMPLETED)
        );

        // Withdraw
        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(intentId);

        assertEq(user1.balance - balBefore, 11 ether, "Should receive 10 principal + 1 yield");
        assertEq(composer.intentBalances(intentId), 0);
    }

    // =========================================================================
    // test_nextIntentId_increments_across_types
    // =========================================================================

    function test_nextIntentId_increments_across_types() public {
        vm.startPrank(user1);

        uint256 id1 = composer.submitIntent{value: 1 ether}(address(0), 0, 500, 30, 0);
        uint256 id2 = composer.submitSwapIntent{value: 2 ether}(
            address(0), 0, address(tokenB), 1 ether, 7
        );
        uint256 id3 = composer.submitIntent{value: 1 ether}(address(0), 0, 800, 60, 0);

        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(composer.nextIntentId(), 4);
    }
}
