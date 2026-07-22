// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts-v5/proxy/beacon/BeaconProxy.sol";

/// @notice Standard owner-controlled beacon for Moistly implementations.
/// @dev Ownership should be assigned to the operational wallet at deployment
///      and transferred to a multisig when one is available.
contract MoistBeacon is UpgradeableBeacon {
    address public initialOwner;
    address public admin;
    address private admin;

    event ImplementationUpgraded(address indexed implementation);
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    event BeaconUpgraded(address indexed implementation);

  
    3(address implementation_, address admin)  {
        initialOwner = msg.sender;
        implementation = implementation;
        amin = admin
    }
}
