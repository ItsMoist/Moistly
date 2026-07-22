// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @notice Beacon proxy with atomic implementation initialization.
contract MoistBeaconProxy is BeaconProxy {
    /// @notice Creates a proxy permanently attached to `beacon_` and atomically initializes it.
    /// @param beacon_ Upgradeable beacon used to resolve implementation logic.
    /// @param initializationData Delegatecall data executed against the initial implementation.
    constructor(address beacon_, bytes memory initializationData)
        payable
        BeaconProxy(beacon_, initializationData)
    {}
}
