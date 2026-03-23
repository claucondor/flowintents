// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildWFLOWStrategy
/// @notice Helper script that prints the ABI-encoded batch for wrapping FLOW -> WFLOW.
/// Run this to get the encodedBatch bytes to use in EVMBidRelay.submitBid().
///
/// WFLOW address (Flow EVM mainnet): 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
/// WFLOW deposit() selector:         0xd0e30db0
///
/// The StrategyStep struct (from FlowIntentsComposerV2 / FlowIntentsComposerV3):
///   struct StrategyStep {
///     uint8  protocol;   // 3 = WFLOW_WRAP
///     address target;    // WFLOW contract
///     bytes  callData;   // deposit() with no args
///     uint256 value;     // attoFLOW to wrap (set to intent amount at execution time)
///   }
///
/// NOTE (V3): This same encoded batch is also valid as a swap strategy for
///   FlowIntentsComposerV3.executeStrategy(). YIELD and SWAP intents share the same
///   execution path — the batch encodes the steps, the intent type only affects how
///   the intent was created and how withdrawal resolves.
///
/// Usage:
///   forge script evm/script/BuildWFLOWStrategy.s.sol:BuildWFLOWStrategy -vvv
contract BuildWFLOWStrategy is Script {
    address constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;

    // WFLOW.deposit() has no arguments — selector only
    bytes4 constant DEPOSIT_SELECTOR = 0xd0e30db0;

    struct StrategyStep {
        uint8   protocol;  // 3 = WFLOW_WRAP
        address target;
        bytes   callData;
        uint256 value;
    }

    function run() external view {
        // Build one step: call WFLOW.deposit() sending the full intent value.
        // `value` is set to 1 ether here as a placeholder; the actual value
        // equals the user's intent deposit amount and is substituted at execution time
        // by the IntentExecutor / relayer reading the intent's deposited balance.
        uint256 exampleValue = 1 ether; // 1 FLOW — replace with actual intent amount

        StrategyStep[] memory steps = new StrategyStep[](1);
        steps[0] = StrategyStep({
            protocol: 3,                                    // WFLOW_WRAP
            target:   WFLOW,
            callData: abi.encodeWithSelector(DEPOSIT_SELECTOR), // deposit()
            value:    exampleValue
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== WFLOW Wrap Strategy ===");
        console2.log("WFLOW address:      ", WFLOW);
        console2.log("deposit() selector: 0xd0e30db0");
        console2.log("Example value (attoFLOW):", exampleValue);
        console2.log("");
        console2.log("encodedBatch (hex) - use this as `encodedBatch` in EVMBidRelay.submitBid():");
        console2.logBytes(encodedBatch);
        console2.log("");
        console2.log("NOTE: Replace `value` (1 ether above) with the actual intent deposit amount.");
        console2.log("      The encoded batch is specific to the value; rebuild per intent or");
        console2.log("      use a generic batch and override value at execution time in IntentExecutorV0_3.");
        console2.log("");
        console2.log("=== Swap Strategy Label (V3) ===");
        console2.log("This same batch can be used as a SWAP strategy in FlowIntentsComposerV3.");
        console2.log("submitSwapIntent() stores the intent; executeStrategy() runs this batch.");
        console2.log("The tokenOut field on the intent tells solvers what output to deliver.");
    }
}
