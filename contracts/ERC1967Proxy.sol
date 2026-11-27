// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC-1967 transparent-style proxy for StorageV2 deployments
///         that pin a fixed implementation instead of a beacon.
contract ERC1967Proxy {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Must match StorageV2.PROXY_OWNER_SLOT.
    bytes32 internal constant PROXY_OWNER_SLOT =
        0x296ff641f9f98e0f3cffd901df5623977f5fe79518952b1b3a2d2596cf3bc2a5;

    error InvalidImplementation(address implementation);
    error InvalidOwner(address owner);

    event Upgraded(address indexed implementation);
    event ProxyOwnerInitialized(address indexed owner);

    constructor(address implementation_, address owner_) payable {
        if (implementation_ == address(0) || implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }

        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }

        if (owner_ != address(0)) {
            if (owner_.code.length != 0) {
                revert InvalidOwner(owner_);
            }
            assembly {
                sstore(PROXY_OWNER_SLOT, owner_)
            }
            emit ProxyOwnerInitialized(owner_);
        }

        emit Upgraded(implementation_);
    }

    function implementation() external view returns (address impl) {
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }

    function _fallback() internal {
        assembly {
            let impl := sload(IMPLEMENTATION_SLOT)
            calldatacopy(0x00, 0x00, calldatasize())
            let ok := delegatecall(gas(), impl, 0x00, calldatasize(), 0x00, 0x00)
            returndatacopy(0x00, 0x00, returndatasize())
            switch ok
            case 0 { revert(0x00, returndatasize()) }
            default { return(0x00, returndatasize()) }
        }
    }
}
