// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FlowIntentsComposerV3
/// @notice Extends V2 with swap intent support. EVM users can now submit either:
///         - Yield intents (submitIntent): deposit tokenIn, earn yield at targetAPY
///         - Swap intents (submitSwapIntent): deposit tokenIn, receive at least minAmountOut of tokenOut
///         Solvers compete by offering the best execution. Cadence ScheduledManager polls
///         getPendingIntents() and dispatches to solvers via the COA bridge.
/// @dev COA addresses on Flow EVM are identifiable by the prefix 0x000000000000000000000002.
///      All privileged callers must be the authorizedCOA set by the owner.
contract FlowIntentsComposerV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants — Known addresses on Flow EVM mainnet (chainId 747)
    // -------------------------------------------------------------------------

    /// @notice LayerZero V2 EndpointV2 on Flow EVM
    /// STRATEGY: AVAILABLE — LayerZero is deployed on Flow EVM mainnet
    address public constant LAYERZERO_ENDPOINT = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa;

    // -------------------------------------------------------------------------
    // LayerZero interface (interface only, no full impl)
    // -------------------------------------------------------------------------

    /// @notice Minimal LayerZero V2 endpoint interface for cross-chain messaging
    /// STRATEGY: AVAILABLE — LayerZero EndpointV2 is live on Flow EVM
    // solhint-disable-next-line no-empty-blocks
    // Defined inline to avoid external dependency

    /// @notice Minimal Stargate router interface for cross-chain swaps
    /// STRATEGY: STUB — Stargate router is not yet deployed on Flow EVM mainnet (chainId 747)

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    /// @notice Which side holds the principal / generates yield
    enum PrincipalSide {
        EVM_YIELD,      // 0 — funds stay on EVM, yield from EVM protocols
        CADENCE_YIELD   // 1 — funds bridge to Cadence side for yield
    }

    /// @notice Protocol identifiers for strategy steps
    enum Protocol {
        MORE,           // 0 — MORE Protocol (lending/yield on Flow EVM)
        STARGATE,       // 1 — Stargate (cross-chain liquidity)
        LAYERZERO,      // 2 — LayerZero (cross-chain messaging)
        WFLOW_WRAP,     // 3 — WFLOW wrap/unwrap
        CUSTOM          // 4 — Any other protocol call
    }

    /// @notice Type of intent: yield-generating or token swap
    enum IntentType {
        YIELD,  // 0 — yield intent (same as V2 submitIntent)
        SWAP    // 1 — swap intent (new in V3)
    }

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice An intent submitted by an EVM user
    struct EVMIntentRequest {
        uint256 id;
        address user;           // EVM user who submitted
        address token;          // EVM token (address(0) = native FLOW)
        uint256 amount;
        uint256 targetAPY;      // basis points (500 = 5%) — used for YIELD intents
        uint256 durationDays;
        uint8 principalSide;    // 0=EVM_YIELD, 1=CADENCE_YIELD — used for YIELD intents
        uint256 submittedAt;
        bool pickedUp;          // true after ScheduledManager reads it
        // V3 additions — swap fields
        IntentType intentType;  // YIELD or SWAP
        address tokenOut;       // for SWAP: desired output token (address(0) = native FLOW)
        uint256 minAmountOut;   // for SWAP: minimum tokens to receive
    }

    /// @notice A single step in a strategy execution batch
    struct StrategyStep {
        uint8 protocol;     // 0=MORE, 1=STARGATE, 2=LAYERZERO, 3=WFLOW_WRAP, 4=CUSTOM
        address target;     // contract to call
        bytes callData;     // encoded call
        uint256 value;      // ETH/FLOW value
    }

    /// @notice Status of an intent on the EVM side
    enum IntentStatus {
        PENDING,        // 0 — awaiting pickup by Cadence
        PICKED_UP,      // 1 — picked up by ScheduledManager
        EXECUTING,      // 2 — strategy is running
        COMPLETED,      // 3 — yield returned, user can withdraw
        CANCELLED       // 4 — user cancelled before pickup
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The single authorized COA address (set by owner)
    address public authorizedCOA;

    /// @notice Reference to the AgentIdentityRegistry (for future validation)
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
        require(msg.sender == authorizedCOA, "FlowIntentsComposerV3: not COA");
        _;
    }

    // -------------------------------------------------------------------------
    // Admin (owner only)
    // -------------------------------------------------------------------------

    /// @notice Set the authorized COA address
    function setAuthorizedCOA(address _coa) external onlyOwner {
        require(_coa != address(0), "FlowIntentsComposerV3: zero COA");
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
        require(targetAPY > 0, "FlowIntentsComposerV3: zero APY");
        require(durationDays > 0, "FlowIntentsComposerV3: zero duration");
        require(principalSide <= 1, "FlowIntentsComposerV3: invalid principalSide");

        uint256 depositAmount;

        if (token == address(0)) {
            // Native FLOW deposit
            require(msg.value > 0, "FlowIntentsComposerV3: no FLOW sent");
            depositAmount = msg.value;
        } else {
            // ERC-20 deposit
            require(amount > 0, "FlowIntentsComposerV3: zero amount");
            require(msg.value == 0, "FlowIntentsComposerV3: no ETH for ERC20");
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
        require(minAmountOut > 0, "FlowIntentsComposerV3: zero minAmountOut");
        require(durationDays > 0, "FlowIntentsComposerV3: zero duration");
        require(tokenIn != tokenOut, "FlowIntentsComposerV3: same token");

        uint256 depositAmount;

        if (tokenIn == address(0)) {
            // Native FLOW as input
            require(msg.value > 0, "FlowIntentsComposerV3: no FLOW sent");
            depositAmount = msg.value;
        } else {
            // ERC-20 as input
            require(amount > 0, "FlowIntentsComposerV3: zero amount");
            require(msg.value == 0, "FlowIntentsComposerV3: no ETH for ERC20");
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
        // First pass: count pending
        uint256 count = 0;
        for (uint256 i = 1; i < nextIntentId; ) {
            if (!_intentRequests[i].pickedUp && intentStatuses[i] == IntentStatus.PENDING) {
                unchecked { count++; }
            }
            unchecked { i++; }
        }

        // Second pass: populate arrays
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
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV3: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(!req.pickedUp, "FlowIntentsComposerV3: already picked up");
        require(intentStatuses[intentId] == IntentStatus.PENDING, "FlowIntentsComposerV3: not pending");

        req.pickedUp = true;
        intentStatuses[intentId] = IntentStatus.PICKED_UP;

        emit IntentPickedUp(intentId);
    }

    /// @notice Execute a strategy batch for an intent. Called by IntentExecutor via COA.
    ///         Works for both YIELD and SWAP intents — the encodedBatch encodes the execution steps.
    /// @param intentId The intent to execute strategy for
    /// @param encodedBatch ABI-encoded array of StrategyStep structs
    /// @return success True if all steps executed successfully
    function executeStrategy(
        uint256 intentId,
        bytes calldata encodedBatch
    ) external onlyCOA nonReentrant returns (bool success) {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV3: invalid intentId");
        require(
            intentStatuses[intentId] == IntentStatus.PICKED_UP ||
            intentStatuses[intentId] == IntentStatus.EXECUTING,
            "FlowIntentsComposerV3: not ready for execution"
        );

        // Decode the strategy steps
        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "FlowIntentsComposerV3: empty batch");

        intentStatuses[intentId] = IntentStatus.EXECUTING;

        uint256 stepsExecuted = 0;

        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];

            (bool ok, ) = step.target.call{value: step.value}(step.callData);

            if (!ok) {
                // On any revert, revert the whole batch
                revert("FlowIntentsComposerV3: strategy step failed");
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
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV3: invalid intentId");
        require(
            intentStatuses[intentId] == IntentStatus.EXECUTING ||
            intentStatuses[intentId] == IntentStatus.PICKED_UP,
            "FlowIntentsComposerV3: not executing"
        );

        intentBalances[intentId] = finalBalance;
        intentStatuses[intentId] = IntentStatus.COMPLETED;

        emit IntentCompleted(intentId, finalBalance);
    }

    // -------------------------------------------------------------------------
    // User Functions
    // -------------------------------------------------------------------------

    /// @notice Withdraw funds — user claims back if cancelled, or claims yield/swap output if completed.
    /// @param intentId The intent to withdraw from
    function withdraw(uint256 intentId) external nonReentrant {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV3: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(req.user == msg.sender, "FlowIntentsComposerV3: not intent owner");
        require(
            intentStatuses[intentId] == IntentStatus.COMPLETED ||
            intentStatuses[intentId] == IntentStatus.CANCELLED,
            "FlowIntentsComposerV3: not withdrawable"
        );

        uint256 amount = intentBalances[intentId];
        require(amount > 0, "FlowIntentsComposerV3: nothing to withdraw");

        intentBalances[intentId] = 0;

        // For SWAP intents that completed: tokenOut is the output token.
        // The solver must have deposited the output token back into the contract
        // and called markCompleted(). The withdraw token is tokenOut (or tokenIn if cancelled).
        address withdrawToken = req.token; // default: original deposit token
        if (req.intentType == IntentType.SWAP && intentStatuses[intentId] == IntentStatus.COMPLETED) {
            withdrawToken = req.tokenOut;
        }

        if (withdrawToken == address(0)) {
            // Native FLOW
            (bool sent, ) = msg.sender.call{value: amount}("");
            require(sent, "FlowIntentsComposerV3: FLOW transfer failed");
        } else {
            // ERC-20
            IERC20(withdrawToken).safeTransfer(msg.sender, amount);
        }

        emit WithdrawalProcessed(intentId, msg.sender, amount);
    }

    /// @notice Cancel a pending intent (before it's picked up by Cadence).
    /// @param intentId The intent to cancel
    function cancelIntent(uint256 intentId) external nonReentrant {
        require(intentId > 0 && intentId < nextIntentId, "FlowIntentsComposerV3: invalid intentId");
        EVMIntentRequest storage req = _intentRequests[intentId];
        require(req.user == msg.sender, "FlowIntentsComposerV3: not intent owner");
        require(intentStatuses[intentId] == IntentStatus.PENDING, "FlowIntentsComposerV3: not pending");

        intentStatuses[intentId] = IntentStatus.CANCELLED;
        uint256 amount = intentBalances[intentId];

        emit IntentCancelled(intentId, msg.sender, amount);
        // User can now call withdraw() to get funds back
    }

    // -------------------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------------------

    /// @notice Get the deposited balance for an intent
    /// @param intentId The intent to query
    /// @return balance The current balance
    function getIntentBalance(uint256 intentId) external view returns (uint256) {
        return intentBalances[intentId];
    }

    /// @notice Get the status of an intent
    /// @param intentId The intent to query
    /// @return status The current status enum value
    function getIntentStatus(uint256 intentId) external view returns (IntentStatus) {
        return intentStatuses[intentId];
    }

    /// @notice Get an intent request by ID
    /// @param intentId The intent to query
    /// @return request The full intent request struct
    function getIntentRequest(uint256 intentId) external view returns (EVMIntentRequest memory) {
        return _intentRequests[intentId];
    }

    // -------------------------------------------------------------------------
    // LayerZero Bridge Helper
    // STRATEGY: AVAILABLE — LayerZero EndpointV2 is live on Flow EVM
    // -------------------------------------------------------------------------

    /// @notice Bridge tokens via LayerZero. Builds LZ message and calls endpoint.send().
    /// @dev Only callable by COA as part of strategy execution.
    /// @param dstEid Destination endpoint ID (LayerZero chain ID)
    /// @param token Token to bridge (must be LZ-compatible OFT)
    /// @param amount Amount to bridge
    /// @param receiver Receiver address as bytes32 (left-padded)
    function bridgeViaLayerZero(
        uint32 dstEid,
        address token,
        uint256 amount,
        bytes32 receiver
    ) external payable onlyCOA {
        // Build the LZ send message
        // For OFT tokens, the message format follows the OFT standard
        bytes memory message = abi.encode(token, amount, receiver);
        bytes memory options = ""; // Default options — solver can customize via strategy steps

        // Call LayerZero endpoint
        ILayerZeroEndpointV3(LAYERZERO_ENDPOINT).send{value: msg.value}(
            dstEid,
            receiver,
            message,
            options,
            msg.sender // refund to COA
        );

        emit LZBridgeInitiated(0, dstEid, amount);
    }

    /// @notice Quote LayerZero fees for a bridge operation
    /// @param dstEid Destination endpoint ID
    /// @param message Encoded message
    /// @param options LZ options
    /// @return nativeFee Fee in native token
    /// @return lzTokenFee Fee in LZ token
    function quoteLZBridge(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee) {
        return ILayerZeroEndpointV3(LAYERZERO_ENDPOINT).quote(
            dstEid,
            message,
            options,
            false // pay in native, not LZ token
        );
    }

    // -------------------------------------------------------------------------
    // Stargate Bridge Helper
    // STRATEGY: STUB — Stargate router not yet deployed on Flow EVM (chainId 747)
    // -------------------------------------------------------------------------

    // Stargate swap functionality is stubbed. When Stargate deploys on Flow EVM,
    // implement the swap helper here using IStargateRouter.swap().
    // For now, cross-chain swaps should use LayerZero OFT directly.

    // -------------------------------------------------------------------------
    // Receive ETH/FLOW (needed for LZ refunds and strategy returns)
    // -------------------------------------------------------------------------

    receive() external payable {}
}

// -------------------------------------------------------------------------
// External Interfaces
// -------------------------------------------------------------------------

/// @notice Minimal LayerZero V2 endpoint interface
/// STRATEGY: AVAILABLE — deployed at 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa on Flow EVM
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
