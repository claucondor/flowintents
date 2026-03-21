// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAgentValidationRegistry} from "./interfaces/IAgentValidationRegistry.sol";
import {IAgentReputationRegistry} from "./interfaces/IAgentReputationRegistry.sol";

/// @title AgentValidationRegistry
/// @notice Records immutable validation evidence for completed intents
/// @dev Called by Cadence via COA after an intent completes. This contract
///      then triggers AgentReputationRegistry.recordCompletion() to update scores.
///      Only registered COA addresses can call recordValidation().
///      Evidence is immutable: once recorded for an intentId it cannot be changed.
contract AgentValidationRegistry is IAgentValidationRegistry, Ownable {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Reference to the reputation registry for score updates
    IAgentReputationRegistry public reputationRegistry;

    /// @notice Whitelist of COA addresses allowed to submit validations
    mapping(address => bool) public authorizedCOAs;

    /// @notice Immutable validation records per intent ID
    mapping(uint256 => ValidationRecord) private _validations;

    // -------------------------------------------------------------------------
    // Events (supplemental)
    // -------------------------------------------------------------------------

    event COAAuthorized(address indexed coa);
    event COARevoked(address indexed coa);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner, address reputationRegistry_)
        Ownable(initialOwner)
    {
        require(
            reputationRegistry_ != address(0),
            "AgentValidationRegistry: zero reputation registry"
        );
        reputationRegistry = IAgentReputationRegistry(reputationRegistry_);
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAuthorizedCOA() {
        require(
            authorizedCOAs[msg.sender],
            "AgentValidationRegistry: caller is not authorized COA"
        );
        _;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Authorize a COA address to submit validations (owner only)
    function authorizeCOA(address coa) external onlyOwner {
        require(coa != address(0), "AgentValidationRegistry: zero address");
        authorizedCOAs[coa] = true;
        emit COAAuthorized(coa);
    }

    /// @notice Revoke a COA address authorization (owner only)
    function revokeCOA(address coa) external onlyOwner {
        authorizedCOAs[coa] = false;
        emit COARevoked(coa);
    }

    /// @notice Update the reputation registry address (owner only)
    function setReputationRegistry(address reputationRegistry_) external onlyOwner {
        require(
            reputationRegistry_ != address(0),
            "AgentValidationRegistry: zero address"
        );
        reputationRegistry = IAgentReputationRegistry(reputationRegistry_);
    }

    // -------------------------------------------------------------------------
    // IAgentValidationRegistry
    // -------------------------------------------------------------------------

    /// @inheritdoc IAgentValidationRegistry
    /// @dev Evidence is immutable: will revert if intentId already has a record.
    ///      Internally calls reputationRegistry.recordCompletion().
    function recordValidation(
        uint256 intentId,
        uint256 solverTokenId,
        uint256 principalReturned,
        uint256 yieldEarned,
        bytes32 evidenceHash
    ) external override onlyAuthorizedCOA {
        require(
            !_validations[intentId].exists,
            "AgentValidationRegistry: intent already validated"
        );

        bool success = (evidenceHash != bytes32(0));

        _validations[intentId] = ValidationRecord({
            intentId: intentId,
            solverTokenId: solverTokenId,
            principalReturned: principalReturned,
            yieldEarned: yieldEarned,
            evidenceHash: evidenceHash,
            timestamp: block.timestamp,
            exists: true
        });

        // Propagate to reputation registry
        reputationRegistry.recordCompletion(solverTokenId, intentId, success);

        emit IntentValidated(intentId, solverTokenId, success);
    }

    /// @inheritdoc IAgentValidationRegistry
    function getValidation(uint256 intentId)
        external
        view
        override
        returns (ValidationRecord memory record)
    {
        return _validations[intentId];
    }
}
