// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentWill} from "../src/AgentWill.sol";
import {MockAgentID} from "../src/MockAgentID.sol";

/// @notice Deploy AgentWill + MockAgentID to BSC Testnet (chain 97).
/// @dev Usage:
///   TESTNET_KEY=<key> forge script script/Deploy.s.sol \
///     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
///     --broadcast -vvvv
/// The deployer becomes the AgentWill owner (emergency pause only).
/// NEVER run this against mainnet without the user's explicit approval.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("TESTNET_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);
        MockAgentID mockId = new MockAgentID();
        console.log("MockAgentID:", address(mockId));
        AgentWill will = new AgentWill(address(mockId));
        console.log("AgentWill:", address(will));
        vm.stopBroadcast();
    }
}
