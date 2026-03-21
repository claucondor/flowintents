// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFlowIntentsComposer} from "./interfaces/IFlowIntentsComposer.sol";

/// @title FlowIntentsComposer
/// @notice Stateless batch executor callable exclusively from Cadence via COA
/// @dev COA addresses on Flow EVM are identifiable by the prefix 0x000000000000000000000002
///      All callers must be pre-registered in the coaAddresses whitelist
///      Each step is executed via low-level call; required steps revert the entire batch on failure
contract FlowIntentsComposer is IFlowIntentsComposer, Ownable, ReentrancyGuard {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Whitelist of Cadence-Owned Account addresses allowed to call executeBatch
    mapping(address => bool) public coaAddresses;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner) Ownable(initialOwner) {}

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @dev Restricts execution to registered COA addresses only
    modifier onlyCOA() {
        require(coaAddresses[msg.sender], "FlowIntentsComposer: caller is not a registered COA");
        _;
    }

    // -------------------------------------------------------------------------
    // COA Management (owner only)
    // -------------------------------------------------------------------------

    /// @notice Register a COA address in the whitelist
    /// @dev On Flow EVM, COA addresses start with 0x000000000000000000000002
    ///      We allow the owner to register any address for flexibility (e.g., testing)
    function registerCOA(address coa) external override onlyOwner {
        require(coa != address(0), "FlowIntentsComposer: zero address");
        coaAddresses[coa] = true;
        emit COARegistered(coa);
    }

    /// @notice Remove a COA address from the whitelist
    function deregisterCOA(address coa) external override onlyOwner {
        coaAddresses[coa] = false;
        emit COADeregistered(coa);
    }

    // -------------------------------------------------------------------------
    // Batch Execution
    // -------------------------------------------------------------------------

    /// @notice Execute a batch of steps on behalf of an intent solver
    /// @dev Only callable by a registered COA (Cadence transaction)
    ///      - required=true steps: revert entire batch on failure
    ///      - required=false steps: log failure and continue
    function executeBatch(
        uint256 intentId,
        BatchStep[] calldata steps,
        address solverIdentity
    ) external override onlyCOA nonReentrant returns (bool success) {
        uint256 len = steps.length;
        require(len > 0, "FlowIntentsComposer: empty batch");

        uint256 stepsExecuted = 0;
        bool hasCrossChain = false;

        for (uint256 i = 0; i < len; ) {
            BatchStep calldata step = steps[i];

            // Detect cross-chain steps heuristically:
            // LayerZero endpoint on Flow EVM = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa
            if (step.target == 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa) {
                hasCrossChain = true;
            }

            (bool ok, ) = step.target.call{value: step.value}(step.callData);

            emit StepExecuted(intentId, i, step.target, ok);

            if (ok) {
                unchecked { stepsExecuted++; }
            } else if (step.required) {
                // Required step failed — revert entire batch
                revert("FlowIntentsComposer: required step failed");
            }
            // If not required and failed: log via event and continue

            unchecked { i++; }
        }

        emit BatchExecuted(intentId, solverIdentity, stepsExecuted, hasCrossChain);
        return true;
    }

    // -------------------------------------------------------------------------
    // Events (internal — not in interface, supplement IFlowIntentsComposer events)
    // -------------------------------------------------------------------------

    event COARegistered(address indexed coa);
    event COADeregistered(address indexed coa);

    // -------------------------------------------------------------------------
    // Receive ETH (needed for steps that return value)
    // -------------------------------------------------------------------------

    receive() external payable {}
}
