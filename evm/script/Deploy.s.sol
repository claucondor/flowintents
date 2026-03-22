// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentIdentityRegistry}   from "../src/AgentIdentityRegistry.sol";
import {AgentReputationRegistry} from "../src/AgentReputationRegistry.sol";
import {AgentValidationRegistry} from "../src/AgentValidationRegistry.sol";
import {FlowIntentsComposer}     from "../src/FlowIntentsComposer.sol";
import {FlowIntentsComposerV2}   from "../src/FlowIntentsComposerV2.sol";
import {EVMBidRelay}             from "../src/EVMBidRelay.sol";

/// @title Deploy
/// @notice Deploys all FlowIntents EVM contracts in the correct dependency order:
///         1. AgentIdentityRegistry
///         2. AgentReputationRegistry  (needs: validation address — set post-deploy)
///         3. AgentValidationRegistry  (needs: reputation address)
///         4. FlowIntentsComposer      (standalone)
///
/// @dev Deployment order matters because of circular dependency between
///      AgentReputationRegistry (needs validationRegistry address) and
///      AgentValidationRegistry (needs reputationRegistry address).
///      Solution: deploy Reputation with placeholder address(1), then deploy
///      Validation, then call setValidationRegistry() on Reputation.
///
/// Usage (local anvil):
///   anvil --fork-url https://mainnet.evm.nodes.onflow.org --chain-id 747 --port 8545
///   forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast -vvv
///
/// Usage (Flow EVM testnet):
///   forge script script/Deploy.s.sol:Deploy --rpc-url https://testnet.evm.nodes.onflow.org \
///     --broadcast --private-key $PRIVATE_KEY -vvv
///
/// Usage (Flow EVM mainnet):
///   forge script script/Deploy.s.sol:Deploy --rpc-url https://mainnet.evm.nodes.onflow.org \
///     --broadcast --private-key $PRIVATE_KEY -vvv
contract Deploy is Script {
    // Known addresses on Flow EVM mainnet (chainId 747)
    // LayerZero V2 EndpointV2
    address constant LAYERZERO_ENDPOINT = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa;

    // MORE Protocol Pool (for test interactions)
    address constant MORE_POOL   = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    // stgUSDC
    address constant STGUSDC     = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    // ankrFLOW
    address constant ANKRFLOW    = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    // WFLOW
    address constant WFLOW       = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;

    function run() external {
        address deployer = vm.envOr("DEPLOYER", msg.sender);
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));

        bool hasPk = deployerKey != 0;

        if (hasPk) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        // ------------------------------------------------------------------
        // Step 1: AgentIdentityRegistry
        // ------------------------------------------------------------------
        AgentIdentityRegistry identityReg = new AgentIdentityRegistry(deployer);
        console2.log("AgentIdentityRegistry deployed at:", address(identityReg));

        // ------------------------------------------------------------------
        // Step 2: AgentReputationRegistry (with placeholder validation address)
        // ------------------------------------------------------------------
        AgentReputationRegistry reputationReg = new AgentReputationRegistry(
            deployer,
            address(1) // placeholder — will be updated after validation deploy
        );
        console2.log("AgentReputationRegistry deployed at:", address(reputationReg));

        // ------------------------------------------------------------------
        // Step 3: AgentValidationRegistry (takes reputation address)
        // ------------------------------------------------------------------
        AgentValidationRegistry validationReg = new AgentValidationRegistry(
            deployer,
            address(reputationReg)
        );
        console2.log("AgentValidationRegistry deployed at:", address(validationReg));

        // Update reputation registry to point to the real validation registry
        reputationReg.setValidationRegistry(address(validationReg));
        console2.log("ReputationRegistry.validationRegistry updated to:", address(validationReg));

        // ------------------------------------------------------------------
        // Step 4: FlowIntentsComposer
        // ------------------------------------------------------------------
        FlowIntentsComposer composer = new FlowIntentsComposer(deployer);
        console2.log("FlowIntentsComposer deployed at:", address(composer));

        // ------------------------------------------------------------------
        // Step 5: FlowIntentsComposerV2 (dual-chain intent submission + strategy execution)
        // ------------------------------------------------------------------
        FlowIntentsComposerV2 composerV2 = new FlowIntentsComposerV2(deployer, address(identityReg));
        console2.log("FlowIntentsComposerV2 deployed at:", address(composerV2));

        // ------------------------------------------------------------------
        // Step 6: EVMBidRelay (permissionless EVM bid board for EVM-only solvers)
        // ------------------------------------------------------------------
        EVMBidRelay evmBidRelay = new EVMBidRelay();
        console2.log("EVMBidRelay deployed at:", address(evmBidRelay));

        vm.stopBroadcast();

        // ------------------------------------------------------------------
        // Write deployment addresses to JSON files
        // ------------------------------------------------------------------
        string memory network = _detectNetwork();
        _writeDeployments(
            network,
            address(identityReg),
            address(reputationReg),
            address(validationReg),
            address(composer),
            address(composerV2),
            address(evmBidRelay)
        );

        // Print summary
        console2.log("\n=== FlowIntents EVM Deployment Summary ===");
        console2.log("Network:                  ", network);
        console2.log("AgentIdentityRegistry:    ", address(identityReg));
        console2.log("AgentReputationRegistry:  ", address(reputationReg));
        console2.log("AgentValidationRegistry:  ", address(validationReg));
        console2.log("FlowIntentsComposer:      ", address(composer));
        console2.log("FlowIntentsComposerV2:    ", address(composerV2));
        console2.log("EVMBidRelay:              ", address(evmBidRelay));
        console2.log("\nKnown Flow EVM addresses:");
        console2.log("LayerZero EndpointV2:     ", LAYERZERO_ENDPOINT);
        console2.log("MORE Protocol Pool:       ", MORE_POOL);
        console2.log("WFLOW:                    ", WFLOW);
        console2.log("stgUSDC:                  ", STGUSDC);
        console2.log("ankrFLOW:                 ", ANKRFLOW);
        console2.log("\nNOTE: ERC-8004 was NOT previously deployed on Flow EVM.");
        console2.log("AgentIdentityRegistry IS the first ERC-8004 deployment on chainId 747.");
    }

    function _detectNetwork() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 747)    return "flow-evm-mainnet";
        if (chainId == 646)    return "flow-evm-testnet";
        if (chainId == 31337)  return "local";
        return "unknown";
    }

    function _writeDeployments(
        string memory network,
        address identityReg,
        address reputationReg,
        address validationReg,
        address composer,
        address composerV2,
        address evmBidRelay
    ) internal {
        string memory json = string.concat(
            '{\n',
            '  "network": "', network, '",\n',
            '  "chainId": ', _uint2str(block.chainid), ',\n',
            '  "deployedAt": ', _uint2str(block.timestamp), ',\n',
            '  "contracts": {\n',
            '    "AgentIdentityRegistry":   "', _addr2str(identityReg),   '",\n',
            '    "AgentReputationRegistry": "', _addr2str(reputationReg), '",\n',
            '    "AgentValidationRegistry": "', _addr2str(validationReg), '",\n',
            '    "FlowIntentsComposer":     "', _addr2str(composer),      '",\n',
            '    "FlowIntentsComposerV2":   "', _addr2str(composerV2),    '",\n',
            '    "EVMBidRelay":             "', _addr2str(evmBidRelay),   '"\n',
            '  },\n',
            '  "knownAddresses": {\n',
            '    "LayerZeroEndpointV2": "', _addr2str(LAYERZERO_ENDPOINT), '",\n',
            '    "MOREProtocolPool":    "', _addr2str(MORE_POOL),          '",\n',
            '    "WFLOW":               "', _addr2str(WFLOW),              '",\n',
            '    "stgUSDC":             "', _addr2str(STGUSDC),            '",\n',
            '    "ankrFLOW":            "', _addr2str(ANKRFLOW),           '"\n',
            '  }\n',
            '}'
        );

        // Always write to local.json when on anvil/local
        if (block.chainid == 31337) {
            vm.writeFile("deployments/local.json", json);
            console2.log("Deployment saved to: deployments/local.json");
        } else if (block.chainid == 646) {
            vm.writeFile("deployments/testnet.json", json);
            console2.log("Deployment saved to: deployments/testnet.json");
        } else if (block.chainid == 747) {
            vm.writeFile("deployments/mainnet.json", json);
            console2.log("Deployment saved to: deployments/mainnet.json");
        } else {
            vm.writeFile("deployments/local.json", json);
            console2.log("Deployment saved to: deployments/local.json");
        }
    }

    // -------------------------------------------------------------------------
    // Minimal string helpers (no external deps)
    // -------------------------------------------------------------------------

    function _addr2str(address a) internal pure returns (string memory) {
        return vm.toString(a);
    }

    function _uint2str(uint256 v) internal pure returns (string memory) {
        return vm.toString(v);
    }
}
