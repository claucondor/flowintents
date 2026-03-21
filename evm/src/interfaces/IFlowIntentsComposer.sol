// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFlowIntentsComposer
/// @notice Interface for the stateless batch executor called from Cadence via COA
interface IFlowIntentsComposer {
    /// @notice Represents a single step in a batch execution
    /// @param target The contract address to call
    /// @param callData The encoded function call data
    /// @param value ETH value to send with the call
    /// @param required If true and the call fails, the entire batch reverts
    struct BatchStep {
        address target;
        bytes callData;
        uint256 value;
        bool required;
    }

    /// @notice Emitted when a full batch completes
    /// @param intentId The intent identifier from Cadence
    /// @param solver The solver identity address
    /// @param stepsExecuted Number of steps successfully executed
    /// @param crossChain Whether the batch involved cross-chain operations
    event BatchExecuted(
        uint256 indexed intentId,
        address indexed solver,
        uint256 stepsExecuted,
        bool crossChain
    );

    /// @notice Emitted for each individual step execution attempt
    /// @param intentId The intent identifier from Cadence
    /// @param stepIndex The index of this step in the batch
    /// @param target The contract that was called
    /// @param success Whether the call succeeded
    event StepExecuted(
        uint256 indexed intentId,
        uint256 stepIndex,
        address target,
        bool success
    );

    /// @notice Execute a batch of steps for a given intent
    /// @param intentId The intent identifier (from Cadence)
    /// @param steps Array of steps to execute
    /// @param solverIdentity The on-chain identity address of the solver
    /// @return success True if all required steps succeeded
    function executeBatch(
        uint256 intentId,
        BatchStep[] calldata steps,
        address solverIdentity
    ) external returns (bool success);

    /// @notice Check if an address is a registered COA
    /// @param addr Address to check
    /// @return True if the address is a whitelisted COA
    function coaAddresses(address addr) external view returns (bool);

    /// @notice Add a COA address to the whitelist (admin only)
    /// @param coa The COA address to register
    function registerCOA(address coa) external;

    /// @notice Remove a COA address from the whitelist (admin only)
    /// @param coa The COA address to deregister
    function deregisterCOA(address coa) external;
}
