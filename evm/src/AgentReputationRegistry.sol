// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAgentReputationRegistry} from "./interfaces/IAgentReputationRegistry.sol";

/// @title AgentReputationRegistry
/// @notice Tracks solver reputation scores for bid scoring via Cadence COA staticCall
/// @dev Score mechanics:
///      - Initial score: 100e18
///      - Success: +10e18 (cap 1000e18)
///      - Failure: -20e18 (floor 10e18)
///      - Multiplier: score / 100e18  (1e18-based, readable by Cadence)
///      ONLY AgentValidationRegistry can call recordCompletion()
contract AgentReputationRegistry is IAgentReputationRegistry, Ownable {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant INITIAL_SCORE = 100e18;
    uint256 public constant SCORE_FLOOR   = 10e18;
    uint256 public constant SCORE_CAP     = 1000e18;
    uint256 public constant SUCCESS_DELTA = 10e18;
    uint256 public constant FAILURE_DELTA = 20e18;
    uint256 public constant MULTIPLIER_BASE = 100e18;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The only address allowed to call recordCompletion
    address public validationRegistry;

    /// @notice Current score per agent token ID
    mapping(uint256 => uint256) private _scores;

    /// @notice Completion history per agent token ID
    mapping(uint256 => uint256) private _completed;
    mapping(uint256 => uint256) private _failed;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner, address validationRegistry_)
        Ownable(initialOwner)
    {
        require(
            validationRegistry_ != address(0),
            "AgentReputationRegistry: zero validation registry"
        );
        validationRegistry = validationRegistry_;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the validation registry address (owner only)
    function setValidationRegistry(address validationRegistry_) external onlyOwner {
        require(
            validationRegistry_ != address(0),
            "AgentReputationRegistry: zero address"
        );
        validationRegistry = validationRegistry_;
    }

    // -------------------------------------------------------------------------
    // IAgentReputationRegistry
    // -------------------------------------------------------------------------

    /// @inheritdoc IAgentReputationRegistry
    /// @dev Only AgentValidationRegistry can call this
    function recordCompletion(uint256 tokenId, uint256 intentId, bool success)
        external
        override
    {
        require(
            msg.sender == validationRegistry,
            "AgentReputationRegistry: caller is not validation registry"
        );

        uint256 currentScore = _getOrInitScore(tokenId);
        uint256 newScore;

        if (success) {
            unchecked {
                newScore = currentScore + SUCCESS_DELTA;
            }
            if (newScore > SCORE_CAP) newScore = SCORE_CAP;
            unchecked { _completed[tokenId]++; }
        } else {
            if (currentScore <= SCORE_FLOOR + FAILURE_DELTA) {
                newScore = SCORE_FLOOR;
            } else {
                unchecked {
                    newScore = currentScore - FAILURE_DELTA;
                }
            }
            unchecked { _failed[tokenId]++; }
        }

        _scores[tokenId] = newScore;

        emit CompletionRecorded(tokenId, intentId, success, newScore);
    }

    /// @inheritdoc IAgentReputationRegistry
    function getScore(uint256 tokenId)
        external
        view
        override
        returns (uint256 score)
    {
        return _getOrInitScoreView(tokenId);
    }

    /// @inheritdoc IAgentReputationRegistry
    /// @dev Returns (score * 1e18) / 100e18 to preserve precision.
    ///      Cadence reads this via staticCall for bid scoring.
    ///      Example: score=200e18 → multiplier=2e18 (2x)
    ///               score=10e18  → multiplier=0.1e18 (0.1x, minimum)
    ///               score=100e18 → multiplier=1e18  (1x, base)
    function getMultiplier(uint256 tokenId)
        external
        view
        override
        returns (uint256 multiplier)
    {
        uint256 score = _getOrInitScoreView(tokenId);
        // Multiply first to avoid integer truncation: 10e18 * 1e18 / 100e18 = 0.1e18
        return score * 1e18 / MULTIPLIER_BASE;
    }

    /// @inheritdoc IAgentReputationRegistry
    function getHistory(uint256 tokenId)
        external
        view
        override
        returns (uint256 completed, uint256 failed)
    {
        return (_completed[tokenId], _failed[tokenId]);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /// @dev Get score, initializing to INITIAL_SCORE if not yet set (state-mutating version)
    function _getOrInitScore(uint256 tokenId) internal returns (uint256) {
        uint256 score = _scores[tokenId];
        if (score == 0) {
            _scores[tokenId] = INITIAL_SCORE;
            return INITIAL_SCORE;
        }
        return score;
    }

    /// @dev Get score for view functions — returns INITIAL_SCORE if not yet set
    function _getOrInitScoreView(uint256 tokenId) internal view returns (uint256) {
        uint256 score = _scores[tokenId];
        return score == 0 ? INITIAL_SCORE : score;
    }
}
