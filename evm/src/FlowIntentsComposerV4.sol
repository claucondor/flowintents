// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal interface for AgentIdentityRegistry to verify registered solvers.
interface IAgentIdentityRegistry {
    /// @notice Returns the NFT token ID owned by `owner`, or 0 if not registered.
    function getTokenByOwner(address owner) external view returns (uint256);
}

/// @title FlowIntentsComposerV4
/// @notice Extends V3 with two new execution paths:
///
///   A) `executeStrategyWithFunds(bytes encodedBatch)` — COA-only, payable.
///      Used when a Cadence-side intent bridges FLOW from a Cadence vault to the
///      COA's EVM balance and then calls this function with msg.value = bridged FLOW.
///      The batch is executed immediately with those funds. Cadence tracks state.
///
///   B) `executeSwapDirect(uint256 intentId, bytes encodedBatch, uint256 offeredAmountOut)`
///      — permissionless for registered agents (no COA required). Any address holding
///      an AgentIdentityRegistry NFT can call this to fill a SWAP intent. The solver
///      runs the batch (which must place `offeredAmountOut` of `intent.tokenOut` into
///      this contract), then this function transfers those tokens to `intent.user` and
///      marks the intent COMPLETED.
///
/// All V3 functions are preserved unchanged.
contract FlowIntentsComposerV4 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants — Known addresses on Flow EVM mainnet (chainId 747)
    // -------------------------------------------------------------------------

    /// @notice LayerZero V2 EndpointV2 on Flow EVM
    address public constant LAYERZERO_ENDPOINT = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa;

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    /// @notice Which side holds the principal / generates yield
    enum PrincipalSide {
        EVM_YIELD,    // 0 — funds stay on EVM, yield from EVM protocols
        CADENCE_YIELD // 1 — funds bridge to Cadence side for yield
    }

    /// @notice Protocol identifiers for strategy steps
    enum Protocol {
        MORE,       // 0 — MORE Protocol (lending/yield on Flow EVM)
        STARGATE,   // 1 — Stargate (cross-chain liquidity)
        LAYERZERO,  // 2 — LayerZero (cross-chain messaging)
        WFLOW_WRAP, // 3 — WFLOW wrap/unwrap
        CUSTOM      // 4 — Any other protocol call
    }

    /// @notice Type of intent: yield-generating or token swap
    enum IntentType {
        YIELD, // 0 — yield intent (same as V2 submitIntent)
        SWAP   // 1 — swap intent (new in V3)
    }

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice An intent submitted by an EVM user
    struct EVMIntentRequest {
        uint256 id;
        address user;          // EVM user who submitted
        address token;         // EVM token (address(0) = native FLOW)
        uint256 amount;
        uint256 targetAPY;     // basis points (500 = 5%) — used for YIELD intents
        uint256 durationDays;
        uint8 principalSide;   // 0=EVM_YIELD, 1=CADENCE_YIELD — used for YIELD intents
        uint256 submittedAt;
        bool pickedUp;         // true after ScheduledManager reads it
        // V3 additions — swap fields
        IntentType intentType; // YIELD or SWAP
        address tokenOut;      // for SWAP: desired output token (address(0) = native FLOW)
        uint256 minAmountOut;  // for SWAP: minimum tokens to receive
    }

    /// @notice A single step in a strategy execution batch
    struct StrategyStep {
        uint8 protocol;   // 0=MORE, 1=STARGATE, 2=LAYERZERO, 3=WFLOW_WRAP, 4=CUSTOM
        address target;   // contract to call
        bytes callData;   // encoded call
        uint256 value;    // ETH/FLOW value
    }

    /// @notice Status of an intent on the EVM side
    enum IntentStatus {
        PENDING,   // 0 — awaiting pickup by Cadence
        PICKED_UP, // 1 — picked up by ScheduledManager
        EXECUTING, // 2 — strategy is running
        COMPLETED, // 3 — yield returned, user can withdraw
        CANCELLED  // 4 — user cancelled before pickup
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The single authorized COA address (set by owner)
    address public authorizedCOA;

    /// @notice AgentIdentityRegistry address — for EVM-only solver verification
    address public identityRegistry;

    /// @notice Intent request storage
    mapping(uint256 => EVMIntentRequest) internal _intentRequests;

    /// @notice Token balances deposited per intent
    mapping(uint256 => uint256) public intentBalances;

    /// @notice Intent status tracking
    mapping(uint256 => IntentStatus) public intentStatuses;

    /// @notice Next intent ID counter
    uint256 public nextIntentId;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event IntentSubmitted(
        uint256 indexed intentId,
        address indexed user,
        address token,
        uint256 amount,
        uint256 targetAPY,
        uint256 durationDays,
        uint8 principalSide
    );

    event SwapIntentCreated(
        uint256 indexed intentId,
        address indexed user,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 durationDays
    );

    event IntentPickedUp(uint256 indexed intentId);
    event IntentCancelled(uint256 indexed intentId, address indexed user, uint256 amountReturned);
    event StrategyExecuted(uint256 indexed intentId, uint256 stepsExecuted, bool success);
    event IntentCompleted(uint256 indexed intentId, uint256 finalBalance);
    event WithdrawalProcessed(uint256 indexed intentId, address indexed user, uint256 amount);
    event COAUpdated(address indexed oldCOA, address indexed newCOA);
    event LZBridgeInitiated(uint256 indexed intentId, uint32 dstEid, uint256 amount);

    // V4 new events
    event CadenceBridgeBatchExecuted(address indexed coa, uint256 value, uint256 stepsExecuted);
    event SwapExecuted(uint256 indexed intentId, address indexed solver, uint256 amountOut);
    event YieldExecuted(uint256 indexed intentId, address indexed solver, uint256 batchLength);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner, address _identityRegistry) Ownable(initialOwner) {
        identityRegistry = _identityRegistry;
        nextIntentId = 1; // Start at 1 so 0 can mean "no intent"
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyCOA() {
        require(msg.sender == authorizedCOA, "FlowIntentsComposerV4: not COA");
        _;
    }

    // -------------------------------------------------------------------------
    // Admin (owner only)
    // -------------------------------------------------------------------------

    /// @notice Set the authorized COA address
    function setAuthorizedCOA(address _coa) external onlyOwner {
        require(_coa != address(0), "FlowIntentsComposerV4: zero COA");
        address old = authorizedCOA;
        authorizedCOA = _coa;
        emit COAUpdated(old, _coa);
    }

    /// @notice Update identity registry reference
    function setIdentityRegistry(address _registry) external onlyOwner {
        identityRegistry = _registry;
    }

    // -------------------------------------------------------------------------
    // Intent Submission (EVM users) — Yield (V2-compatible)
    // -------------------------------------------------------------------------

    /// @notice Submit a yield intent from the EVM side. For native FLOW: send value with token=address(0).
    ///         For ERC-20: approve this contract first, then call with the token address.
    /// @param token ERC-20 token address, or address(0) for native FLOW
    /// @param amount Amount to deposit (ignored for native FLOW — uses msg.value)
    /// @param targetAPY Target APY in basis points (e.g., 500 = 5%)
    /// @param durationDays How many days to run the strategy
    /// @param principalSide 0=EVM_YIELD, 1=CADENCE_YIELD
    /// @return intentId The ID of the newly created intent
    function submitIntent(
        address token,
        uint256 amount,
        uint256 targetAPY,
        uint256 durationDays,
        uint8 principalSide
    ) external payable nonReentrant returns (uint256 intentId) {
        require(targetAPY > 0, "FlowIntentsComposerV4: zero APY");
        require(durationDays > 0, "FlowIntentsComposerV4: zero duration");
        require(principalSide <= 1, "FlowIntentsComposerV4: invalid principalSide");

        uint256 depositAmount;

        if (token == address(0)) {
            require(msg.value > 0, "FlowIntentsComposerV4: no FLOW sent");
            depositAmount = msg.value;
        } else {
            require(amount > 0, "FlowIntentsComposerV4: zero amount");
            require(msg.value == 0, "FlowIntentsComposerV4: no ETH for ERC20");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            depositAmount = amount;
        }

        intentId = nextIntentId;
        unchecked { nextIntentId++; }

        _intentRequests[intentId] = EVMIntentRequest({
            id: intentId,
            user: msg.sender,
            token: token,
            amount: depositAmount,
            targetAPY: targetAPY,
            durationDays: durationDays,
            principalSide: principalSide,
            submittedAt: block.timestamp,
            pickedUp: false,
            intentType: IntentType.YIELD,
            tokenOut: address(0),
            minAmountOut: 0
        });

        intentBalances[intentId] = depositAmount;
        intentStatuses[intentId] = IntentStatus.PENDING;

        emit IntentSubmitted(
            intentId,
            msg.sender,
            token,
            depositAmount,
            targetAPY,
            durationDays,
            principalSide
        );
    }

    // -------------------------------------------------------------------------
    // Intent Submission (EVM users) — Swap (V3 new)
    // -------------------------------------------------------------------------

    /// @notice Create a swap intent: deposit tokenIn, receive at least minAmountOut of tokenOut.
    ///         Solvers compete by offering the highest amountOut.
    /// @param tokenIn  Input token. address(0) = native FLOW.
    /// @param amount   Amount of tokenIn to deposit. Ignored for native FLOW (uses msg.value).
    /// @param tokenOut Output token. address(0) = native FLOW.
    /// @param minAmountOut Minimum acceptable output amount.
    /// @param durationDays How long solvers have to fill the order.
    /// @return intentId The ID of the newly created swap intent
    function submitSwapIntent(
        address tokenIn,
        uint256 amount,
        address tokenOut,
        uint256 minAmountOut,
        uint256 durationDays
    ) external payable nonReentrant returns (uint256 intentId) {
        require(minAmountOut > 0, "FlowIntentsComposerV4: zero minAmountOut");
        require(durationDays > 0, "FlowIntentsComposerV4: zero duration");
        require(tokenIn != tokenOut, "FlowIntentsComposerV4: same token");

        uint256 depositAmount;

        if (tokenIn == address(0)) {
            require(msg.value > 0, "FlowIntentsComposerV4: no FLOW sent");
            depositAmount = msg.value;
        } else {
            require(amount > 0, "FlowIntentsComposerV4: zero amount");
            require(msg.value == 0, "FlowIntentsComposerV4: no ETH for ERC20");
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
            depositAmount = amount;
        }

        intentId = nextIntentId;
        unchecked { nextIntentId++; }

        _intentRequests[intentId] = EVMIntentRequest({
            id: intentId,
            user: msg.sender,
            token: tokenIn,
            amount: depositAmount,
            targetAPY: 0,
            durationDays: durationDays,
            principalSide: 0,
            submittedAt: block.timestamp,
            pickedUp: false,
            intentType: IntentType.SWAP,
            tokenOut: tokenOut,
            minAmountOut: minAmountOut
        });

        intentBalances[intentId] = depositAmount;
        intentStatuses[intentId] = IntentStatus.PENDING;

        emit SwapIntentCreated(
            intentId,
            msg.sender,
            tokenIn,
            depositAmount,
            tokenOut,
            minAmountOut,
            durationDays
        );
    }

    // -------------------------------------------------------------------------
    // Cadence Integration (COA-only)
    // -------------------------------------------------------------------------

    /// @notice Returns all pending (not yet picked up) intents.
    ///         Designed for COA staticCall from ScheduledManager.
    /// @return ids Array of pending intent IDs
    /// @return requests Array of corresponding intent request structs
    function getPendingIntents()
        external
        view
        returns (uint256[] memory ids, EVMIntentRequest[] memory requests)
    {
        uint256 count = 0;
        for (uint256 i = 1; i < nextIntentId; ) {
            if (!_intentRequests[i].pickedUp && intentStatuses[i] == IntentStatus.PENDING) {
                unchecked { count++; }
            }
            unchecked { i++; }
        }

        ids = new uint256[](count);
        requests = new EVMIntentRequest[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i < nextIntentId; ) {
            if (!_intentRequests[i].pickedUp && intentStatuses[i] == IntentStatus.PENDING) {
                ids[idx] = i;
                requests[idx] = _intentRequests[i];
                unchecked { idx++; }
            }
            unchecked { i++; }
        }
    }

    /// @notice Mark an intent as picked up by the Cadence ScheduledManager.
    ///         Only callable by the authorized COA.
    /// @param intentId The intent to mark as picked up
    function markPickedUp(uint256 intentId) external onlyCOA {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(!req.pickedUp, "FlowIntentsComposerV4: already picked up");
        require(intentStatuses[intentId] == IntentStatus.PENDING, "FlowIntentsComposerV4: not pending");

        req.pickedUp = true;
        intentStatuses[intentId] = IntentStatus.PICKED_UP;

        emit IntentPickedUp(intentId);
    }

    /// @notice Execute a strategy batch for an EVM-originated intent. COA-only.
    ///         Works for both YIELD and SWAP intents via the Cadence COA bridge.
    /// @param intentId The intent to execute strategy for
    /// @param encodedBatch ABI-encoded array of StrategyStep structs
    /// @return success True if all steps executed successfully
    function executeStrategy(
        uint256 intentId,
        bytes calldata encodedBatch
    ) external onlyCOA nonReentrant returns (bool success) {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        require(
            intentStatuses[intentId] == IntentStatus.PICKED_UP ||
            intentStatuses[intentId] == IntentStatus.EXECUTING,
            "FlowIntentsComposerV4: not ready for execution"
        );

        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "FlowIntentsComposerV4: empty batch");

        intentStatuses[intentId] = IntentStatus.EXECUTING;

        uint256 stepsExecuted = 0;

        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];

            (bool ok, ) = step.target.call{value: step.value}(step.callData);

            if (!ok) {
                revert("FlowIntentsComposerV4: strategy step failed");
            }

            unchecked {
                stepsExecuted++;
                i++;
            }
        }

        emit StrategyExecuted(intentId, stepsExecuted, true);
        return true;
    }

    /// @notice Mark an intent as completed. Called by COA after yield/swap is returned.
    /// @param intentId The intent to complete
    /// @param finalBalance The final balance available for withdrawal
    function markCompleted(uint256 intentId, uint256 finalBalance) external onlyCOA {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        require(
            intentStatuses[intentId] == IntentStatus.EXECUTING ||
            intentStatuses[intentId] == IntentStatus.PICKED_UP,
            "FlowIntentsComposerV4: not executing"
        );

        intentBalances[intentId] = finalBalance;
        intentStatuses[intentId] = IntentStatus.COMPLETED;

        emit IntentCompleted(intentId, finalBalance);
    }

    // -------------------------------------------------------------------------
    // V4 NEW: executeStrategyWithFunds — Cadence-side bridge execution
    // -------------------------------------------------------------------------

    /// @notice Execute a strategy batch with bridged FLOW from a Cadence vault.
    ///         Called by the Cadence IntentExecutor's COA after depositing the
    ///         principal vault balance into the COA's EVM balance and sending it
    ///         as msg.value in a coa.call(). Cadence tracks intent state — no
    ///         EVM-side intent ID is required here.
    ///
    ///         Selector: 0x7954fae9
    ///
    /// @param encodedBatch ABI-encoded array of StrategyStep structs.
    ///                     Steps receive msg.value via the first step's `value` field
    ///                     or can reference this contract's balance directly.
    /// @return success True if all steps executed without reverting
    function executeStrategyWithFunds(
        bytes calldata encodedBatch
    ) external payable onlyCOA nonReentrant returns (bool success) {
        require(msg.value > 0, "FlowIntentsComposerV4: no FLOW bridged");

        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "FlowIntentsComposerV4: empty batch");

        uint256 stepsExecuted = 0;

        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];

            (bool ok, ) = step.target.call{value: step.value}(step.callData);

            if (!ok) {
                revert("FlowIntentsComposerV4: strategy step failed");
            }

            unchecked {
                stepsExecuted++;
                i++;
            }
        }

        emit CadenceBridgeBatchExecuted(msg.sender, msg.value, stepsExecuted);
        return true;
    }

    // -------------------------------------------------------------------------
    // V4 NEW: executeSwapDirect — permissionless EVM-only solver execution
    // -------------------------------------------------------------------------

    /// @notice Fill an EVM-side SWAP intent directly without going through the COA.
    ///         Any registered agent (AgentIdentityRegistry NFT holder) can call this.
    ///
    ///         Flow:
    ///           1. Caller must be a registered agent.
    ///           2. Intent must be a SWAP intent in PENDING or PICKED_UP status.
    ///           3. offeredAmountOut >= intent.minAmountOut.
    ///           4. encodedBatch is executed — batch must result in >= offeredAmountOut
    ///              of intent.tokenOut landing in this contract (or the solver must have
    ///              pre-approved this contract for ERC-20 transfers).
    ///           5. offeredAmountOut of tokenOut is transferred to intent.user.
    ///           6. Intent marked COMPLETED.
    ///
    ///         Selector: 0x2fb08e6b
    ///
    /// @param intentId The EVM intent to fill
    /// @param encodedBatch ABI-encoded StrategyStep[] for the swap execution
    /// @param offeredAmountOut Amount of tokenOut the solver guarantees to deliver
    function executeSwapDirect(
        uint256 intentId,
        bytes calldata encodedBatch,
        uint256 offeredAmountOut
    ) external nonReentrant {
        // --- 1. Verify caller is a registered agent ---
        require(
            identityRegistry != address(0),
            "FlowIntentsComposerV4: identity registry not set"
        );
        require(
            IAgentIdentityRegistry(identityRegistry).getTokenByOwner(msg.sender) > 0,
            "FlowIntentsComposerV4: caller not a registered agent"
        );

        // --- 2. Validate intent ---
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        EVMIntentRequest storage intent = _intentRequests[intentId];

        require(intent.intentType == IntentType.SWAP, "FlowIntentsComposerV4: not a SWAP intent");
        require(
            intentStatuses[intentId] == IntentStatus.PENDING ||
            intentStatuses[intentId] == IntentStatus.PICKED_UP,
            "FlowIntentsComposerV4: intent not fillable"
        );

        // --- 3. Validate offered output meets minimum ---
        require(
            offeredAmountOut >= intent.minAmountOut,
            "FlowIntentsComposerV4: offeredAmountOut below minAmountOut"
        );

        // --- 4. Execute the batch (solver's swap logic) ---
        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "FlowIntentsComposerV4: empty batch");

        // Mark as executing before external calls
        intentStatuses[intentId] = IntentStatus.EXECUTING;

        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];

            (bool ok, ) = step.target.call{value: step.value}(step.callData);

            if (!ok) {
                revert("FlowIntentsComposerV4: swap step failed");
            }

            unchecked { i++; }
        }

        // --- 5. Transfer offeredAmountOut of tokenOut to intent.user ---
        address tokenOut = intent.tokenOut;
        address user = intent.user;

        if (tokenOut == address(0)) {
            // Native FLOW output — contract must hold sufficient balance after the batch
            require(
                address(this).balance >= offeredAmountOut,
                "FlowIntentsComposerV4: insufficient native FLOW for payout"
            );
            (bool sent, ) = payable(user).call{value: offeredAmountOut}("");
            require(sent, "FlowIntentsComposerV4: native FLOW transfer failed");
        } else {
            // ERC-20 output — contract must hold sufficient tokenOut after the batch
            IERC20(tokenOut).safeTransfer(user, offeredAmountOut);
        }

        // --- 6. Mark intent completed ---
        intentBalances[intentId] = offeredAmountOut;
        intentStatuses[intentId] = IntentStatus.COMPLETED;

        emit SwapExecuted(intentId, msg.sender, offeredAmountOut);
    }

    // -------------------------------------------------------------------------
    // V4 NEW: executeYieldDirect — permissionless EVM-only yield execution
    // -------------------------------------------------------------------------

    /// @notice Fill an EVM-side YIELD intent directly without going through COA.
    ///         Any registered agent (AgentIdentityRegistry NFT holder) can call this.
    ///         Funds are already in this contract from the user's submitIntent() call.
    ///         The batch executes the yield strategy (e.g. deposit to MORE, wrap to WFLOW).
    ///         Intent moves to EXECUTING state — yield is active until duration expires or
    ///         the solver calls a future withdraw/settle function.
    ///
    ///         Selector: 0x9a7b81cf
    ///
    /// @param intentId The EVM YIELD intent to execute
    /// @param encodedBatch ABI-encoded StrategyStep[] for the yield strategy
    function executeYieldDirect(
        uint256 intentId,
        bytes calldata encodedBatch
    ) external nonReentrant {
        // 1. Caller must be registered agent
        require(identityRegistry != address(0), "identity registry not set");
        require(
            IAgentIdentityRegistry(identityRegistry).getTokenByOwner(msg.sender) > 0,
            "caller not a registered agent"
        );

        // 2. Validate intent
        require(intentId > 0 && intentId < nextIntentId, "invalid intentId");
        EVMIntentRequest storage intent = _intentRequests[intentId];
        require(intent.intentType == IntentType.YIELD, "not a YIELD intent");
        require(
            intentStatuses[intentId] == IntentStatus.PICKED_UP ||
            intentStatuses[intentId] == IntentStatus.PENDING,
            "intent not ready for yield execution"
        );

        // 3. Execute the strategy batch
        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "empty batch");

        intentStatuses[intentId] = IntentStatus.EXECUTING;

        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];
            (bool ok, ) = step.target.call{value: step.value}(step.callData);
            if (!ok) revert("yield step failed");
            unchecked { i++; }
        }

        emit YieldExecuted(intentId, msg.sender, encodedBatch.length);
    }

    // -------------------------------------------------------------------------
    // User Functions
    // -------------------------------------------------------------------------

    /// @notice Withdraw funds — user claims back if cancelled, or claims yield/swap output if completed.
    /// @param intentId The intent to withdraw from
    function withdraw(uint256 intentId) external nonReentrant {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(req.user == msg.sender, "FlowIntentsComposerV4: not intent owner");
        require(
            intentStatuses[intentId] == IntentStatus.COMPLETED ||
            intentStatuses[intentId] == IntentStatus.CANCELLED,
            "FlowIntentsComposerV4: not withdrawable"
        );

        uint256 amount = intentBalances[intentId];
        require(amount > 0, "FlowIntentsComposerV4: nothing to withdraw");

        intentBalances[intentId] = 0;

        // For SWAP intents that completed: tokenOut is the output token.
        // The solver must have deposited the output token back into the contract.
        address withdrawToken = req.token; // default: original deposit token
        if (req.intentType == IntentType.SWAP && intentStatuses[intentId] == IntentStatus.COMPLETED) {
            withdrawToken = req.tokenOut;
        }

        if (withdrawToken == address(0)) {
            (bool sent, ) = msg.sender.call{value: amount}("");
            require(sent, "FlowIntentsComposerV4: FLOW transfer failed");
        } else {
            IERC20(withdrawToken).safeTransfer(msg.sender, amount);
        }

        emit WithdrawalProcessed(intentId, msg.sender, amount);
    }

    /// @notice Cancel a pending intent (before it's picked up by Cadence).
    /// @param intentId The intent to cancel
    function cancelIntent(uint256 intentId) external nonReentrant {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV4: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(req.user == msg.sender, "FlowIntentsComposerV4: not intent owner");
        require(intentStatuses[intentId] == IntentStatus.PENDING, "FlowIntentsComposerV4: not pending");

        intentStatuses[intentId] = IntentStatus.CANCELLED;

        emit IntentCancelled(intentId, msg.sender, intentBalances[intentId]);
    }

    // -------------------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------------------

    /// @notice Get the deposited balance for an intent
    function getIntentBalance(uint256 intentId) external view returns (uint256) {
        return intentBalances[intentId];
    }

    /// @notice Get the status of an intent
    function getIntentStatus(uint256 intentId) external view returns (IntentStatus) {
        return intentStatuses[intentId];
    }

    /// @notice Get an intent request by ID
    function getIntentRequest(uint256 intentId) external view returns (EVMIntentRequest memory) {
        return _intentRequests[intentId];
    }

    // -------------------------------------------------------------------------
    // LayerZero Bridge Helper
    // STRATEGY: AVAILABLE — LayerZero EndpointV2 is live on Flow EVM
    // -------------------------------------------------------------------------

    /// @notice Bridge tokens via LayerZero. Builds LZ message and calls endpoint.send().
    /// @dev Only callable by COA as part of strategy execution.
    function bridgeViaLayerZero(
        uint32 dstEid,
        address token,
        uint256 amount,
        bytes32 receiver
    ) external payable onlyCOA {
        bytes memory message = abi.encode(token, amount, receiver);
        bytes memory options = "";

        ILayerZeroEndpointV3(LAYERZERO_ENDPOINT).send{value: msg.value}(
            dstEid,
            receiver,
            message,
            options,
            msg.sender
        );

        emit LZBridgeInitiated(0, dstEid, amount);
    }

    /// @notice Quote LayerZero fees for a bridge operation
    function quoteLZBridge(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee) {
        return ILayerZeroEndpointV3(LAYERZERO_ENDPOINT).quote(
            dstEid,
            message,
            options,
            false
        );
    }

    // -------------------------------------------------------------------------
    // Receive ETH/FLOW
    // -------------------------------------------------------------------------

    receive() external payable {}
}

// -------------------------------------------------------------------------
// External Interfaces
// -------------------------------------------------------------------------

/// @notice Minimal LayerZero V2 endpoint interface
interface ILayerZeroEndpointV3 {
    function send(
        uint32 dstEid,
        bytes32 receiver,
        bytes calldata message,
        bytes calldata options,
        address refundAddress
    ) external payable;

    function quote(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options,
        bool payInLzToken
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
}

/// @notice Minimal Stargate router interface
/// STRATEGY: STUB — not yet deployed on Flow EVM (chainId 747)
interface IStargateRouterV3 {
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        bytes calldata _to
    ) external payable;
}
