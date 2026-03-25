// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {FlowIntentsComposerV4} from "../src/FlowIntentsComposerV4.sol";

contract DeployComposerV4 is Script {
    /// @notice AgentIdentityRegistry on Flow EVM mainnet (chainId 747)
    address public constant AGENT_IDENTITY_REGISTRY = 0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223;

    function run() external {
        uint256 deployerKey = uint256(vm.envBytes32("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.envOr("DEPLOYER", vm.addr(deployerKey));

        vm.startBroadcast(deployerKey);

        FlowIntentsComposerV4 v4 = new FlowIntentsComposerV4(deployer, AGENT_IDENTITY_REGISTRY);

        console2.log("FlowIntentsComposerV4 deployed at:", address(v4));
        console2.log("Owner:", deployer);
        console2.log("IdentityRegistry:", AGENT_IDENTITY_REGISTRY);

        vm.stopBroadcast();
    }
}
