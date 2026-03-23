// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {FlowIntentsComposerV3} from "../src/FlowIntentsComposerV3.sol";

contract DeployComposerV3 is Script {
    function run() external {
        address deployer = vm.envOr("DEPLOYER", msg.sender);
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerKey != 0) vm.startBroadcast(deployerKey);
        else vm.startBroadcast();

        FlowIntentsComposerV3 v3 = new FlowIntentsComposerV3(deployer, address(0)); // address(0) = no identity registry required for now
        console2.log("FlowIntentsComposerV3 deployed at:", address(v3));
        vm.stopBroadcast();
    }
}
