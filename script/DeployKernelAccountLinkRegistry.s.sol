// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {KernelAccountLinkRegistry} from "../contracts/KernelAccountLinkRegistry.sol";

/// @notice Deployment entrypoint. Broadcast only after tests, review, and chain/address checks.
contract DeployKernelAccountLinkRegistry is Script {
    function run() external returns (KernelAccountLinkRegistry registry) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address expectedDeployer = vm.envAddress("EXPECTED_DEPLOYER");
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        require(block.chainid == expectedChainId, "unexpected chain id");
        require(vm.addr(deployerKey) == expectedDeployer, "deployer key/address mismatch");

        vm.startBroadcast(deployerKey);
        registry = new KernelAccountLinkRegistry();
        vm.stopBroadcast();

        require(address(registry).code.length > 0, "deployment has no code");
        require(registry.domainSeparator() != bytes32(0), "domain separator invalid");
    }
}
