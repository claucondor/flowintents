// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentValidationRegistry
/// @notice Records immutable validation evidence for completed intents
///         Called by Cadence via COA after intent completion
interface IAgentValidationRegistry {
    /// @notice Immutable validation record stored per intent
    struct ValidationRecord {
        uint256 intentId;
        uint256 solverTokenId;
        uint256 principalReturned;  // in wei
        uint256 yieldEarned;        // in wei
        bytes32 evidenceHash;       // keccak256 of off-chain evidence
        uint256 timestamp;
        bool exists;
    }

    /// @notice Emitted when an intent is validated
    event IntentValidated(
        uint256 indexed intentId,
        uint256 indexed solverTokenId,
        bool success
    );

    /// @notice Record validation evidence for a completed intent
    /// @dev Only callable by a registered COA (Cadence calls this on completion)
    /// @param intentId The intent identifier
    /// @param solverTokenId The solver's agent token ID
    /// @param principalReturned Amount of principal returned to user (wei)
    /// @param yieldEarned Amount of yield earned (wei)
    /// @param evidenceHash keccak256 hash of off-chain execution evidence
    function recordValidation(
        uint256 intentId,
        uint256 solverTokenId,
        uint256 principalReturned,
        uint256 yieldEarned,
        bytes32 evidenceHash
    ) external;

    /// @notice Retrieve the validation record for a specific intent
    /// @param intentId The intent identifier
    /// @return record The ValidationRecord struct (check record.exists)
    function getValidation(uint256 intentId)
        external
        view
        returns (ValidationRecord memory record);
}
