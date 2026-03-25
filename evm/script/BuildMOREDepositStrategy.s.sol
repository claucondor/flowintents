// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildMOREDepositStrategy
/// @notice Helper script that prints the ABI-encoded batch for depositing into MORE Protocol.
/// Run this to get the encodedBatch bytes to use in EVMBidRelay.submitBid().
///
/// MORE Protocol Pool (Flow EVM mainnet): 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d
/// MORE is an Aave v2/v3 fork.
///
/// Aave v2 supply function:
///   deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
///   selector: keccak256("deposit(address,uint256,address,uint16)") = 0xe8eda9df
///
/// Aave v3 supply function:
///   supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
///   selector: keccak256("supply(address,uint256,address,uint16)") = 0x617ba037
///
/// NOTE: MORE Protocol is an Aave v3 fork (confirmed via ADDRESSES_PROVIDER() returning
///       0x1830a96466d1d108935865c75B0a9548681Cfd9A on mainnet).
///       Both supply() (0x617ba037) and deposit() (0xe8eda9df) selectors are live —
///       both return error code 26 (INVALID_AMOUNT) when called with amount=0.
///       Use supply() (0x617ba037) as the canonical Aave v3 selector.
///       WFLOW is the primary yield asset on Flow EVM for MORE.
///       Output token: mFlowWFLOW (More Flow WFLOW) @ 0x02BF4bd075c1b7C8D85F54777eaAA3638135c059
///
/// The StrategyStep struct (from FlowIntentsComposerV2):
///   struct StrategyStep {
///     uint8  protocol;   // 0 = MORE
///     address target;    // MORE pool address
///     bytes  callData;   // deposit(wflow, amount, receiver, 0)
///     uint256 value;     // 0 for ERC-20 deposits (requires prior approve)
///   }
///
/// IMPORTANT: ERC-20 deposits require a prior approve() step.
/// Add an approve step BEFORE the deposit step, or use FLOW (native) path.
/// For native FLOW strategy: wrap FLOW to WFLOW first (use BuildWFLOWStrategy),
/// then deposit WFLOW into MORE.
///
/// Usage:
///   forge script evm/script/BuildMOREDepositStrategy.s.sol:BuildMOREDepositStrategy -vvv
contract BuildMOREDepositStrategy is Script {
    address constant MORE_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    address constant WFLOW     = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;

    // Aave v2 deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
    bytes4 constant DEPOSIT_SELECTOR = 0xe8eda9df;

    // Aave v3 supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
    bytes4 constant SUPPLY_SELECTOR  = 0x617ba037;

    // ERC-20 approve(address spender, uint256 amount)
    bytes4 constant APPROVE_SELECTOR = 0x095ea7b3;

    struct StrategyStep {
        uint8   protocol;  // 0 = MORE, 4 = CUSTOM
        address target;
        bytes   callData;
        uint256 value;
    }

    function run() external view {
        uint256 exampleAmount    = 1 ether; // 1 WFLOW — replace with actual intent amount
        address exampleReceiver  = address(0xDEAD); // replace with intent user / COA address

        // Step 1: approve MORE pool to spend WFLOW
        StrategyStep[] memory steps = new StrategyStep[](2);
        steps[0] = StrategyStep({
            protocol: 4,         // CUSTOM (ERC-20 approve on WFLOW)
            target:   WFLOW,
            callData: abi.encodeWithSelector(APPROVE_SELECTOR, MORE_POOL, exampleAmount),
            value:    0
        });

        // Step 2: deposit WFLOW into MORE pool (Aave v2 interface)
        steps[1] = StrategyStep({
            protocol: 0,         // MORE
            target:   MORE_POOL,
            callData: abi.encodeWithSelector(
                DEPOSIT_SELECTOR,
                WFLOW,           // asset
                exampleAmount,   // amount
                exampleReceiver, // onBehalfOf
                uint16(0)        // referralCode
            ),
            value: 0             // ERC-20, no native FLOW value
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== MORE Protocol Deposit Strategy (WFLOW) ===");
        console2.log("MORE Pool address:    ", MORE_POOL);
        console2.log("WFLOW address:        ", WFLOW);
        console2.log("deposit() selector:    0xe8eda9df  (Aave v2)");
        console2.log("supply()  selector:    0x617ba037  (Aave v3, fallback)");
        console2.log("Example amount (attoFLOW/WFLOW):", exampleAmount);
        console2.log("Example receiver:     ", exampleReceiver);
        console2.log("");
        console2.log("encodedBatch (hex) - 2-step: approve WFLOW + deposit into MORE:");
        console2.logBytes(encodedBatch);
        console2.log("");
        console2.log("Steps:");
        console2.log("  [0] CUSTOM  - WFLOW.approve(MORE_POOL, amount)");
        console2.log("  [1] MORE    - MORE_POOL.deposit(WFLOW, amount, receiver, 0)");
        console2.log("");
        console2.log("NOTE: Rebuild this batch for each intent with the correct amount and receiver.");
        console2.log("      If MORE is Aave v3, replace deposit selector with supply (0x617ba037).");
    }
}
