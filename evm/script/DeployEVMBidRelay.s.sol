// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {EVMBidRelay} from "../src/EVMBidRelay.sol";

contract DeployEVMBidRelay is Script {
    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerKey != 0) vm.startBroadcast(deployerKey);
        else vm.startBroadcast();

        EVMBidRelay relay = new EVMBidRelay();
        console2.log("EVMBidRelay deployed at:", address(relay));
        vm.stopBroadcast();
    }
}
