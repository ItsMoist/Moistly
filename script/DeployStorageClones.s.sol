// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {StorageV2} from "../contracts/StorageV2.sol";
import {StorageBeacon} from "../contracts/StorageBeacon.sol";
import {StorageCloneFactory} from "../contracts/StorageCloneFactory.sol";

/// @notice Deploys StorageV2 + StorageBeacon + StorageCloneFactory.
/// @dev Broadcast with:
///   forge script script/DeployStorageClones.s.sol:DeployStorageClones \
///     --rpc-url "$ELYSIUM_RPC" --broadcast --private-key "$DEPLOYER_PRIVATE_KEY"
contract DeployStorageClones is Script {
    function run() external returns (address implementation, address beacon, address factory) {
        address owner = vm.envOr("STORAGE_BEACON_OWNER", address(0));

        vm.startBroadcast();
        if (owner == address(0)) {
            owner = msg.sender;
        }

        StorageV2 impl = new StorageV2();
        StorageBeacon storageBeacon = new StorageBeacon(address(impl), owner);
        StorageCloneFactory cloneFactory = new StorageCloneFactory(address(storageBeacon));
        vm.stopBroadcast();

        implementation = address(impl);
        beacon = address(storageBeacon);
        factory = address(cloneFactory);

        console2.log("chainId", block.chainid);
        console2.log("owner", owner);
        console2.log("StorageV2", implementation);
        console2.log("StorageBeacon", beacon);
        console2.log("StorageCloneFactory", factory);
    }
}
