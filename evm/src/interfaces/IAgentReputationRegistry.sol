// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentReputationRegistry
/// @notice Tracks solver reputation scores, readable via COA staticCall from Cadence
interface IAgentReputationRegistry {
    /// @notice Emitted when a completion is recorded
    event CompletionRecorded(
        uint256 indexed tokenId,
        uint256 indexed intentId,
        bool success,
        uint256 newScore
    );

    /// @notice Record an intent completion (success or failure)
    /// @dev Only callable by AgentValidationRegistry
    /// @param tokenId The solver's agent token ID
    /// @param intentId The intent that was executed
    /// @param success Whether the intent was completed successfully
    function recordCompletion(uint256 tokenId, uint256 intentId, bool success) external;

    /// @notice Get the current reputation score for an agent
    /// @dev Score is 1e18-based. Initial = 100e18, min = 10e18, max = 1000e18
    /// @param tokenId The agent token ID
    /// @return score The current score (1e18 precision)
    function getScore(uint256 tokenId) external view returns (uint256 score);

    /// @notice Get the bid multiplier for an agent based on reputation
    /// @dev Returns score / 100e18. e.g., score=200e18 → multiplier=2e18
    ///      Cadence reads this via COA staticCall for bid scoring
    /// @param tokenId The agent token ID
    /// @return multiplier 1e18-based multiplier
    function getMultiplier(uint256 tokenId) external view returns (uint256 multiplier);

    /// @notice Get historical completion counts
    /// @param tokenId The agent token ID
    /// @return completed Number of successfully completed intents
    /// @return failed Number of failed intents
    function getHistory(uint256 tokenId)
        external
        view
        returns (uint256 completed, uint256 failed);
}
