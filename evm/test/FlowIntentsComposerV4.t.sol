// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FlowIntentsComposerV4} from "../src/FlowIntentsComposerV4.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal ERC20 mock for swap intent tests
contract MockERC20V4 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock that places tokenOut into the composer during a swap batch step.
///         Used to simulate a real solver depositing tokenOut after the swap.
contract MockSwapRouter {
    FlowIntentsComposerV4 public composer;
    MockERC20V4 public tokenOut;
    uint256 public depositAmount;

    constructor(address _composer, address _tokenOut, uint256 _depositAmount) {
        composer = FlowIntentsComposerV4(payable(_composer));
        tokenOut = MockERC20V4(_tokenOut);
        depositAmount = _depositAmount;
    }

    /// @notice Called by executeSwapDirect batch — mints/transfers tokenOut to composer
    function executeSwap() external {
        tokenOut.mint(address(composer), depositAmount);
    }

    /// @notice Called by executeStrategyWithFunds batch — just records success
    function executeStrategy() external payable returns (bool) {
        return true;
    }
}

/// @title FlowIntentsComposerV4Test
/// @notice Tests for V4 — covers new executeStrategyWithFunds and executeSwapDirect
///         plus regression tests verifying V3 functions still work.
contract FlowIntentsComposerV4Test is Test {
    FlowIntentsComposerV4 public composer;
    AgentIdentityRegistry public identityReg;

    MockERC20V4 public tokenA; // tokenIn for ERC20 swap tests
    MockERC20V4 public tokenB; // tokenOut for ERC20 swap tests

    address public owner;
    address public user1;
    address public user2;
    address public mockCOA;
    address public mockMOREPool;
    address public registeredSolver;
    address public unregisteredSolver;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockCOA = makeAddr("mockCOA");
        mockMOREPool = makeAddr("mockMOREPool");
        registeredSolver = makeAddr("registeredSolver");
        unregisteredSolver = makeAddr("unregisteredSolver");

        // Deploy identity registry
        identityReg = new AgentIdentityRegistry(owner);

        // Deploy V4 with identity registry
        composer = new FlowIntentsComposerV4(owner, address(identityReg));
        composer.setAuthorizedCOA(mockCOA);

        // Deploy mock tokens
        tokenA = new MockERC20V4("TokenA", "TKA");
        tokenB = new MockERC20V4("TokenB", "TKB");

        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(mockCOA, 200 ether);
        vm.deal(address(composer), 10 ether);
        vm.deal(registeredSolver, 10 ether);
        vm.deal(unregisteredSolver, 10 ether);

        // Mint ERC20s for users
        tokenA.mint(user1, 1000 ether);
        tokenA.mint(user2, 1000 ether);
        tokenB.mint(address(composer), 500 ether);

        // Register one solver in the identity registry
        vm.prank(registeredSolver);
        identityReg.register();
    }

    // =========================================================================
    // PHASE 1 — test_executeStrategyWithFunds_fromCOA
    // =========================================================================

    /// @notice COA bridges FLOW and calls executeStrategyWithFunds with msg.value.
    ///         Verifies the batch runs and the event is emitted.
    function test_executeStrategyWithFunds_fromCOA() public {
        // Build a simple batch that calls a mock target
        address mockTarget = makeAddr("mockTarget");
        vm.mockCall(
            mockTarget,
            abi.encodeWithSignature("doSomething()"),
            abi.encode(true)
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4, // CUSTOM
            target: mockTarget,
            callData: abi.encodeWithSignature("doSomething()"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);
        uint256 bridgedValue = 5 ether;

        vm.expectEmit(true, false, false, true);
        emit FlowIntentsComposerV4.CadenceBridgeBatchExecuted(mockCOA, bridgedValue, 1);

        vm.prank(mockCOA);
        bool success = composer.executeStrategyWithFunds{value: bridgedValue}(encodedBatch);

        assertTrue(success, "executeStrategyWithFunds should return true");
    }

    /// @notice executeStrategyWithFunds must revert if called without bridged FLOW.
    function test_executeStrategyWithFunds_revert_noValue() public {
        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("target"),
            callData: "",
            value: 0
        });

        vm.prank(mockCOA);
        vm.expectRevert("FlowIntentsComposerV4: no FLOW bridged");
        composer.executeStrategyWithFunds{value: 0}(abi.encode(steps));
    }

    /// @notice executeStrategyWithFunds must revert for non-COA callers.
    function test_executeStrategyWithFunds_revert_notCOA() public {
        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("target"),
            callData: "",
            value: 0
        });

        vm.prank(user1);
        vm.expectRevert("FlowIntentsComposerV4: not COA");
        composer.executeStrategyWithFunds{value: 1 ether}(abi.encode(steps));
    }

    /// @notice COA can forward bridged FLOW through a batch step (e.g. deposit into strategy).
    function test_executeStrategyWithFunds_forwardsValue() public {
        address payable mockVault = payable(makeAddr("mockVault"));

        // Mock the vault to accept ETH
        vm.mockCall(
            mockVault,
            abi.encodeWithSignature("deposit()"),
            abi.encode(true)
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 0, // MORE
            target: mockVault,
            callData: abi.encodeWithSignature("deposit()"),
            value: 3 ether // forward 3 FLOW to vault
        });

        bytes memory encodedBatch = abi.encode(steps);

        vm.deal(address(composer), 5 ether); // ensure composer has balance

        vm.prank(mockCOA);
        bool success = composer.executeStrategyWithFunds{value: 5 ether}(encodedBatch);
        assertTrue(success);
    }

    // =========================================================================
    // PHASE 2 — test_executeSwapDirect_registeredSolver
    // =========================================================================

    /// @notice Registered solver successfully fills a SWAP intent.
    function test_executeSwapDirect_registeredSolver() public {
        // Create a swap intent: user1 deposits 5 FLOW, wants tokenB back (min 100)
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),       // tokenIn = native FLOW
            0,
            address(tokenB),  // tokenOut = tokenB
            100 ether,        // minAmountOut
            7                 // 7 days
        );
        assertEq(intentId, 1);

        // Deploy a mock swap router that puts tokenB into composer when called
        MockSwapRouter mockRouter = new MockSwapRouter(
            address(composer),
            address(tokenB),
            150 ether // solver delivers 150 tokenB (above min of 100)
        );

        // Build the batch: call mockRouter.executeSwap() which mints tokenB to composer
        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4, // CUSTOM
            target: address(mockRouter),
            callData: abi.encodeWithSignature("executeSwap()"),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);
        uint256 offeredAmount = 150 ether;

        uint256 user1BalBefore = tokenB.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit FlowIntentsComposerV4.SwapExecuted(intentId, registeredSolver, offeredAmount);

        vm.prank(registeredSolver);
        composer.executeSwapDirect(intentId, encodedBatch, offeredAmount);

        // Verify user received tokenB
        uint256 user1BalAfter = tokenB.balanceOf(user1);
        assertEq(user1BalAfter - user1BalBefore, offeredAmount, "User should receive offeredAmountOut of tokenB");

        // Verify intent status is COMPLETED
        assertEq(
            uint8(composer.getIntentStatus(intentId)),
            uint8(FlowIntentsComposerV4.IntentStatus.COMPLETED),
            "Intent should be COMPLETED"
        );

        // Verify intentBalances updated
        assertEq(composer.getIntentBalance(intentId), offeredAmount);
    }

    // =========================================================================
    // PHASE 3 — test_executeSwapDirect_revert_unregisteredSolver
    // =========================================================================

    /// @notice Unregistered solver attempting executeSwapDirect must revert.
    function test_executeSwapDirect_revert_unregisteredSolver() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),
            0,
            address(tokenB),
            100 ether,
            7
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(unregisteredSolver);
        vm.expectRevert("FlowIntentsComposerV4: caller not a registered agent");
        composer.executeSwapDirect(intentId, abi.encode(steps), 100 ether);
    }

    // =========================================================================
    // PHASE 4 — test_executeSwapDirect_revert_belowMinAmountOut
    // =========================================================================

    /// @notice offeredAmountOut below minAmountOut must revert.
    function test_executeSwapDirect_revert_belowMinAmountOut() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),
            0,
            address(tokenB),
            100 ether, // minAmountOut = 100
            7
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(registeredSolver);
        vm.expectRevert("FlowIntentsComposerV4: offeredAmountOut below minAmountOut");
        composer.executeSwapDirect(
            intentId,
            abi.encode(steps),
            99 ether // below minAmountOut
        );
    }

    /// @notice executeSwapDirect must revert on non-SWAP intents.
    function test_executeSwapDirect_revert_notSwapIntent() public {
        // Submit a YIELD intent
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 5 ether}(
            address(0),
            0,
            500, // 5% APY
            30,
            0
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(registeredSolver);
        vm.expectRevert("FlowIntentsComposerV4: not a SWAP intent");
        composer.executeSwapDirect(intentId, abi.encode(steps), 100 ether);
    }

    // =========================================================================
    // PHASE 5 — test_allV3FunctionsStillWork
    // =========================================================================

    /// @notice Verifies submitIntent, submitSwapIntent, markPickedUp, executeStrategy all work in V4.
    function test_allV3FunctionsStillWork() public {
        // --- submitIntent (yield) ---
        vm.prank(user1);
        uint256 yieldId = composer.submitIntent{value: 10 ether}(
            address(0), 0, 500, 30, 0
        );
        assertEq(yieldId, 1);
        assertEq(uint8(composer.getIntentStatus(yieldId)), uint8(FlowIntentsComposerV4.IntentStatus.PENDING));

        // --- submitSwapIntent ---
        vm.prank(user2);
        uint256 swapId = composer.submitSwapIntent{value: 3 ether}(
            address(0), 0, address(tokenB), 50 ether, 7
        );
        assertEq(swapId, 2);
        assertEq(uint8(composer.getIntentStatus(swapId)), uint8(FlowIntentsComposerV4.IntentStatus.PENDING));

        // --- getPendingIntents ---
        (uint256[] memory ids, ) = composer.getPendingIntents();
        assertEq(ids.length, 2);

        // --- markPickedUp ---
        vm.prank(mockCOA);
        composer.markPickedUp(yieldId);
        assertEq(uint8(composer.getIntentStatus(yieldId)), uint8(FlowIntentsComposerV4.IntentStatus.PICKED_UP));

        // --- executeStrategy ---
        address mockVault = makeAddr("mockVaultV4");
        vm.mockCall(
            mockVault,
            abi.encodeWithSignature("deposit()"),
            abi.encode(true)
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 0, // MORE
            target: mockVault,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });

        vm.prank(mockCOA);
        bool success = composer.executeStrategy(yieldId, abi.encode(steps));
        assertTrue(success);
        assertEq(uint8(composer.getIntentStatus(yieldId)), uint8(FlowIntentsComposerV4.IntentStatus.EXECUTING));

        // --- markCompleted ---
        vm.deal(address(composer), 20 ether);
        vm.prank(mockCOA);
        composer.markCompleted(yieldId, 11 ether);
        assertEq(uint8(composer.getIntentStatus(yieldId)), uint8(FlowIntentsComposerV4.IntentStatus.COMPLETED));

        // --- withdraw ---
        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(yieldId);
        assertEq(user1.balance - balBefore, 11 ether);
    }

    // =========================================================================
    // Additional edge case tests
    // =========================================================================

    /// @notice executeSwapDirect fills a PICKED_UP (not just PENDING) swap intent.
    function test_executeSwapDirect_worksOnPickedUpIntent() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),
            0,
            address(tokenB),
            100 ether,
            7
        );

        // COA marks it picked up
        vm.prank(mockCOA);
        composer.markPickedUp(intentId);
        assertEq(uint8(composer.getIntentStatus(intentId)), uint8(FlowIntentsComposerV4.IntentStatus.PICKED_UP));

        // Registered solver fills it anyway
        MockSwapRouter mockRouter = new MockSwapRouter(
            address(composer),
            address(tokenB),
            120 ether
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: address(mockRouter),
            callData: abi.encodeWithSignature("executeSwap()"),
            value: 0
        });

        vm.prank(registeredSolver);
        composer.executeSwapDirect(intentId, abi.encode(steps), 120 ether);

        assertEq(uint8(composer.getIntentStatus(intentId)), uint8(FlowIntentsComposerV4.IntentStatus.COMPLETED));
        assertEq(tokenB.balanceOf(user1), 120 ether);
    }

    /// @notice cancelIntent + withdraw still works for CANCELLED intent.
    function test_cancelIntent_andWithdraw() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        vm.prank(user1);
        composer.cancelIntent(intentId);
        assertEq(uint8(composer.getIntentStatus(intentId)), uint8(FlowIntentsComposerV4.IntentStatus.CANCELLED));

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        composer.withdraw(intentId);
        assertEq(user1.balance - balBefore, 5 ether);
    }

    // =========================================================================
    // executeYieldDirect tests
    // =========================================================================

    /// @notice Registered agent successfully fills a YIELD intent via executeYieldDirect.
    function test_executeYieldDirect_success() public {
        // user1 submits a YIELD intent
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 10 ether}(
            address(0), // native FLOW
            0,
            500,  // 5% APY
            30,   // 30 days
            0     // EVM_YIELD
        );
        assertEq(intentId, 1);
        assertEq(uint8(composer.getIntentStatus(intentId)), uint8(FlowIntentsComposerV4.IntentStatus.PENDING));

        // Build a batch: call a mock vault's deposit()
        address mockVault = makeAddr("mockYieldVault");
        vm.mockCall(
            mockVault,
            abi.encodeWithSignature("deposit()"),
            abi.encode(true)
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 0, // MORE
            target: mockVault,
            callData: abi.encodeWithSignature("deposit()"),
            value: 0
        });
        bytes memory encodedBatch = abi.encode(steps);

        vm.expectEmit(true, true, false, true);
        emit FlowIntentsComposerV4.YieldExecuted(intentId, registeredSolver, encodedBatch.length);

        vm.prank(registeredSolver);
        composer.executeYieldDirect(intentId, encodedBatch);

        // Intent should now be EXECUTING
        assertEq(
            uint8(composer.getIntentStatus(intentId)),
            uint8(FlowIntentsComposerV4.IntentStatus.EXECUTING),
            "Intent should be EXECUTING after executeYieldDirect"
        );
    }

    /// @notice Unregistered address calling executeYieldDirect must revert.
    function test_executeYieldDirect_notRegistered_reverts() public {
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 5 ether}(
            address(0), 0, 500, 30, 0
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(unregisteredSolver);
        vm.expectRevert("caller not a registered agent");
        composer.executeYieldDirect(intentId, abi.encode(steps));
    }

    /// @notice executeYieldDirect on a SWAP intent must revert.
    function test_executeYieldDirect_notYield_reverts() public {
        vm.prank(user1);
        uint256 intentId = composer.submitSwapIntent{value: 5 ether}(
            address(0),
            0,
            address(tokenB),
            100 ether,
            7
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(registeredSolver);
        vm.expectRevert("not a YIELD intent");
        composer.executeYieldDirect(intentId, abi.encode(steps));
    }

    /// @notice executeYieldDirect on a COMPLETED intent must revert.
    function test_executeYieldDirect_wrongStatus_reverts() public {
        // Submit YIELD intent
        vm.prank(user1);
        uint256 intentId = composer.submitIntent{value: 5 ether}(
            address(0), 0, 500, 30, 0
        );

        // COA marks it picked up then completed
        vm.prank(mockCOA);
        composer.markPickedUp(intentId);

        vm.prank(mockCOA);
        composer.markCompleted(intentId, 5 ether);

        assertEq(uint8(composer.getIntentStatus(intentId)), uint8(FlowIntentsComposerV4.IntentStatus.COMPLETED));

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(registeredSolver);
        vm.expectRevert("intent not ready for yield execution");
        composer.executeYieldDirect(intentId, abi.encode(steps));
    }

    /// @notice nextIntentId increments correctly across multiple submissions.
    function test_nextIntentId_increments() public {
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

    /// @notice executeStrategyWithFunds with empty batch reverts.
    function test_executeStrategyWithFunds_revert_emptyBatch() public {
        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](0);

        vm.prank(mockCOA);
        vm.expectRevert("FlowIntentsComposerV4: empty batch");
        composer.executeStrategyWithFunds{value: 1 ether}(abi.encode(steps));
    }

    /// @notice executeSwapDirect with identity registry at address(0) reverts.
    function test_executeSwapDirect_revert_noRegistry() public {
        // Deploy composer without registry
        FlowIntentsComposerV4 noRegComposer = new FlowIntentsComposerV4(owner, address(0));
        noRegComposer.setAuthorizedCOA(mockCOA);
        vm.deal(address(noRegComposer), 5 ether);

        vm.prank(user1);
        noRegComposer.submitSwapIntent{value: 5 ether}(
            address(0), 0, address(tokenB), 100 ether, 7
        );

        FlowIntentsComposerV4.StrategyStep[] memory steps = new FlowIntentsComposerV4.StrategyStep[](1);
        steps[0] = FlowIntentsComposerV4.StrategyStep({
            protocol: 4,
            target: makeAddr("dummy"),
            callData: "",
            value: 0
        });

        vm.prank(registeredSolver);
        vm.expectRevert("FlowIntentsComposerV4: identity registry not set");
        noRegComposer.executeSwapDirect(1, abi.encode(steps), 100 ether);
    }
}
