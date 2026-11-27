// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StorageBeacon} from "./StorageBeacon.sol";

/// @notice Moistly-facing alias for the storage clone beacon.
/// @dev Prefer deploying `StorageBeacon` directly. This wrapper keeps the
///      historical name while using the fixed owner-controlled implementation.
contract MoistBeacon is StorageBeacon {
    constructor(address implementation_, address owner_) StorageBeacon(implementation_, owner_) {}
}
