// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title FlowIntentsComposerV5
/// @notice Permissionless strategy executor — any COA can call.
///         Executes a batch of StrategySteps with bridged FLOW (msg.value)
///         and sweeps only the DELTA of output ERC-20 tokens to the recipient.
///         Safe for concurrent users — each user only receives their own output.
contract FlowIntentsComposerV5 is ReentrancyGuard {

    struct StrategyStep {
        uint8 protocol;
        address target;
        bytes callData;
        uint256 value;
    }

    event BatchExecuted(address indexed caller, uint256 value, uint256 stepsExecuted, uint256 tokensSwept);

    /// @notice Execute a strategy batch with bridged FLOW.
    ///         Permissionless — any address can call.
    ///         Sweeps only the delta (new tokens produced by this batch) to recipient.
    /// @param encodedBatch ABI-encoded StrategyStep[]
    /// @param recipient Address to sweep output ERC-20 tokens to.
    function executeStrategyWithFunds(
        bytes calldata encodedBatch,
        address recipient
    ) external payable nonReentrant returns (bool) {
        require(msg.value > 0, "no FLOW bridged");

        StrategyStep[] memory steps = abi.decode(encodedBatch, (StrategyStep[]));
        require(steps.length > 0, "empty batch");

        // Collect unique token addresses from step targets
        // (deduplicate to avoid double-sweeping)
        address[] memory tokens = new address[](steps.length);
        uint256 tokenCount = 0;
        for (uint256 i = 0; i < steps.length; ) {
            address t = steps[i].target;
            bool exists = false;
            for (uint256 j = 0; j < tokenCount; ) {
                if (tokens[j] == t) { exists = true; break; }
                unchecked { j++; }
            }
            if (!exists) {
                tokens[tokenCount] = t;
                unchecked { tokenCount++; }
            }
            unchecked { i++; }
        }

        // Snapshot balances BEFORE execution
        uint256[] memory balancesBefore = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; ) {
            (bool ok, bytes memory data) = tokens[i].staticcall(
                abi.encodeWithSelector(0x70a08231, address(this))
            );
            if (ok && data.length == 32) {
                balancesBefore[i] = abi.decode(data, (uint256));
            }
            unchecked { i++; }
        }

        // Execute all steps
        uint256 stepsExecuted = 0;
        for (uint256 i = 0; i < steps.length; ) {
            StrategyStep memory step = steps[i];
            (bool ok, ) = step.target.call{value: step.value}(step.callData);
            if (!ok) revert("step failed");
            unchecked { stepsExecuted++; i++; }
        }

        // Sweep only the DELTA to recipient
        uint256 tokensSwept = 0;
        if (recipient != address(0)) {
            for (uint256 i = 0; i < tokenCount; ) {
                (bool ok, bytes memory data) = tokens[i].staticcall(
                    abi.encodeWithSelector(0x70a08231, address(this))
                );
                if (ok && data.length == 32) {
                    uint256 balAfter = abi.decode(data, (uint256));
                    if (balAfter > balancesBefore[i]) {
                        uint256 delta = balAfter - balancesBefore[i];
                        (bool tok, ) = tokens[i].call(
                            abi.encodeWithSelector(0xa9059cbb, recipient, delta)
                        );
                        require(tok, "sweep failed");
                        unchecked { tokensSwept += delta; }
                    }
                }
                unchecked { i++; }
            }
        }

        emit BatchExecuted(msg.sender, msg.value, stepsExecuted, tokensSwept);
        return true;
    }

    receive() external payable {}
}
