// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildSwapStrategy
/// @notice Helper script that prints an ABI-encoded StrategyStep batch for a single-step
///         swap via any target contract and selector.
///
/// This is the generic version — pass in any swap router address + calldata selector.
/// Use it to build the `encodedBatch` argument for:
///   - FlowIntentsComposerV3.executeStrategy(intentId, encodedBatch)
///   - EVMBidRelay.submitBid(..., encodedBatch)
///
/// The StrategyStep struct (from FlowIntentsComposerV3):
///   struct StrategyStep {
///     uint8   protocol;  // 4 = CUSTOM
///     address target;    // swap router address
///     bytes   callData;  // swap function call
///     uint256 value;     // attoFLOW to send (0 for ERC20 swaps)
///   }
///
/// Example — WFLOW wrap as a swap strategy (FLOW -> WFLOW):
///   target:   0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e  (WFLOW on Flow EVM)
///   selector: 0xd0e30db0  (deposit())
///   value:    <intent deposit amount in attoFLOW>
///
/// Usage:
///   forge script evm/script/BuildSwapStrategy.s.sol:BuildSwapStrategy \
///     --sig "run(address,bytes4,uint256,uint256)" \
///     <target> <selector> <value> <ethValue> -vvv
contract BuildSwapStrategy is Script {
    struct StrategyStep {
        uint8   protocol;  // 4 = CUSTOM
        address target;
        bytes   callData;
        uint256 value;
    }

    /// @notice Build a single-step swap batch with a no-argument selector.
    /// @param target     The swap router or protocol contract to call.
    /// @param selector   The 4-byte function selector (e.g. 0xd0e30db0 for deposit()).
    /// @param value      Native FLOW (in attoFLOW) to forward with the call (0 for ERC20).
    /// @param exampleEth Ignored — kept for CLI ergonomics so callers can pass 0.
    function run(
        address target,
        bytes4 selector,
        uint256 value,
        uint256 exampleEth
    ) external view {
        (exampleEth); // suppress unused variable warning

        StrategyStep[] memory steps = new StrategyStep[](1);
        steps[0] = StrategyStep({
            protocol: 4,                                     // CUSTOM
            target:   target,
            callData: abi.encodeWithSelector(selector),
            value:    value
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== Generic Swap Strategy (single step) ===");
        console2.log("target:   ", target);
        console2.log("selector (bytes4): ");
        console2.logBytes4(selector);
        console2.log("value (attoFLOW): ", value);
        console2.log("");
        console2.log("encodedBatch (hex) - use as `encodedBatch` in executeStrategy() or submitBid():");
        console2.logBytes(encodedBatch);
        console2.log("");
        console2.log("NOTE: For swaps requiring arguments (e.g. swapExactTokensForTokens),");
        console2.log("      extend this script to ABI-encode the full callData with arguments.");
    }

    /// @notice Build a single-step swap batch with full arbitrary callData.
    /// @param target    The swap router or protocol contract to call.
    /// @param callData  Fully encoded calldata (selector + arguments).
    /// @param value     Native FLOW (in attoFLOW) to forward with the call.
    function runWithCallData(
        address target,
        bytes calldata callData,
        uint256 value
    ) external view {
        StrategyStep[] memory steps = new StrategyStep[](1);
        steps[0] = StrategyStep({
            protocol: 4,      // CUSTOM
            target:   target,
            callData: callData,
            value:    value
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== Generic Swap Strategy (full calldata) ===");
        console2.log("target:   ", target);
        console2.log("value (attoFLOW): ", value);
        console2.log("callData (hex): ");
        console2.logBytes(callData);
        console2.log("");
        console2.log("encodedBatch (hex):");
        console2.logBytes(encodedBatch);
    }
}
