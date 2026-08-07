// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBeacon {
    function implementation() external view returns (address);
}

/// @notice Minimal EIP-1967 beacon proxy for deterministic deployments.
contract ERC1967BeaconProxy {
    bytes32 internal constant BEACON_SLOT =
        0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    error InvalidBeacon(address beacon);
    error InvalidImplementation(address implementation);
    error InitializerDelegateCallBlocked();

    event BeaconConfigured(address indexed beacon, address indexed implementation);

    constructor(address beacon_, bytes memory data) payable {
        if (beacon_.code.length == 0) {
            revert InvalidBeacon(beacon_);
        }
        if (data.length != 0) {
            revert InitializerDelegateCallBlocked();
        }

        address implementation_ = IBeacon(beacon_).implementation();
        if (implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }

        assembly {
            sstore(BEACON_SLOT, beacon_)
        }

        emit BeaconConfigured(beacon_, implementation_);
    }

    function beacon() external view returns (address beacon_) {
        assembly {
            beacon_ := sload(BEACON_SLOT)
        }
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }

    function _fallback() internal {
        address implementation_ = _implementation();
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function _implementation() internal view returns (address implementation_) {
        address beacon_;
        assembly {
            beacon_ := sload(BEACON_SLOT)
        }

        implementation_ = IBeacon(beacon_).implementation();
        if (implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }
    }
}
