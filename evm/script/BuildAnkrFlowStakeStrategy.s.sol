// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildAnkrFlowStakeStrategy
/// @notice Helper script that prints the ABI-encoded batch for staking FLOW -> ankrFLOW
///         (certificate token = "Ankr Reward Earning FLOW EVM", symbol aFLOWEVMb).
///
/// Ankr FlowStakingPool (proxy, Flow EVM mainnet): 0xfe8189a3016cb6a3668b8ccdac520ce572d4287a
///   Implementation: FlowStakingPool @ 0xD812aB5EB22425749a972450f5E5cb8BD82cb4e4
///   Verified 2024-10-10 on evm.flowscan.io
///
/// Certificate token (aFLOWEVMb):  0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A
/// Bond token (ankrFLOWEVM):        0x1b97100eA1D7126C4d60027e231EA4CB25314bdb
///
/// IMPORTANT: stakeBonds() is currently PAUSED on mainnet.
///            Use stakeCerts() to stake FLOW and receive aFLOWEVMb (cert token).
///
/// stakeCerts() is payable — send FLOW as `value`, no args required.
/// selector: keccak256("stakeCerts()") = 0xac76d450
///
/// The strategy:
///   1. Call staking_pool.stakeCerts() with the full intent value in FLOW
///   2. Receive aFLOWEVMb certificate token
///
/// Usage:
///   forge script evm/script/BuildAnkrFlowStakeStrategy.s.sol:BuildAnkrFlowStakeStrategy -vvv
contract BuildAnkrFlowStakeStrategy is Script {
    // Ankr FlowStakingPool proxy (Flow EVM mainnet)
    address constant STAKING_POOL = 0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a;

    // Cert token minted by stakeCerts() — "Ankr Reward Earning FLOW EVM" (aFLOWEVMb)
    address constant CERT_TOKEN   = 0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A;

    // Bond token (paused) — "Ankr Staked FLOW EVM" (ankrFLOWEVM)
    address constant BOND_TOKEN   = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;

    // stakeCerts() — payable, no arguments
    bytes4 constant STAKE_CERTS   = 0xac76d450;

    struct StrategyStep {
        uint8   protocol; // 5 = ANKR_STAKE
        address target;
        bytes   callData;
        uint256 value;    // attoFLOW to stake
    }

    function run() external view {
        uint256 exampleValue = 0.5 ether; // 0.5 FLOW — replace with actual intent amount

        StrategyStep[] memory steps = new StrategyStep[](1);
        steps[0] = StrategyStep({
            protocol: 5,                                      // ANKR_STAKE
            target:   STAKING_POOL,
            callData: abi.encodeWithSelector(STAKE_CERTS),   // stakeCerts()
            value:    exampleValue
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== Ankr FlowStaking Stake Strategy (FLOW -> aFLOWEVMb) ===");
        console2.log("FlowStakingPool proxy:  ", STAKING_POOL);
        console2.log("Cert token (aFLOWEVMb): ", CERT_TOKEN);
        console2.log("Bond token (ankrFLOWEVM, paused):", BOND_TOKEN);
        console2.log("stakeCerts() selector:   0xac76d450");
        console2.log("Example value (attoFLOW):", exampleValue);
        console2.log("");
        console2.log("encodedBatch (hex) - use this as `encodedBatch` in EVMBidRelay.submitBid():");
        console2.logBytes(encodedBatch);
        console2.log("");
        console2.log("Steps:");
        console2.log("  [0] ANKR_STAKE - StakingPool.stakeCerts{value: amount}()");
        console2.log("      Sends FLOW natively, receives aFLOWEVMb (cert token)");
        console2.log("");
        console2.log("NOTE: stakeBonds() is paused on mainnet - use stakeCerts() only.");
        console2.log("      Rebuild this batch for each intent with the correct FLOW amount.");
        console2.log("      getMinStake() returns 0, so any amount > 0 should be accepted.");
        console2.log("");
        console2.log("VERIFICATION (cast calls that confirm liveness):");
        console2.log("  getFreeBalance():  ~32805 FLOW in pool");
        console2.log("  owner():           0x2a369e0a05F31Dff22d155aFDFeA8d2C96DB607D");
        console2.log("  getTokens():       (aFLOWEVMb, ankrFLOWEVM)");
    }
}
