// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Gas-lean EIP-1967 beacon proxy for StorageV2 clones.
/// @dev Stores the beacon in the canonical EIP-1967 beacon slot. Optionally
///      writes the StorageV2 proxy-owner slot at construction so clones skip a
///      separate `initializeProxyOwner` transaction.
contract ERC1967BeaconProxy {
    /// @dev EIP-1967 beacon slot: keccak256("eip1967.proxy.beacon") - 1
    bytes32 internal constant BEACON_SLOT =
        0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @dev Must match StorageV2.PROXY_OWNER_SLOT.
    bytes32 internal constant PROXY_OWNER_SLOT =
        0x296ff641f9f98e0f3cffd901df5623977f5fe79518952b1b3a2d2596cf3bc2a5;

    error InvalidBeacon(address beacon);
    error InvalidImplementation(address implementation);
    error InvalidOwner(address owner);

    event Upgraded(address indexed implementation);
    event ProxyOwnerInitialized(address indexed owner);

    /// @param beacon_ Upgradeable beacon that resolves StorageV2 (or successor) logic.
    /// @param owner_ Optional StorageV2 owner written into PROXY_OWNER_SLOT. Use
    ///        address(0) to defer ownership to `StorageV2.initializeProxyOwner()`.
    constructor(address beacon_, address owner_) payable {
        if (beacon_.code.length == 0) {
            revert InvalidBeacon(beacon_);
        }

        address implementation_ = _readImplementation(beacon_);
        if (implementation_ == address(0) || implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }

        assembly {
            sstore(BEACON_SLOT, beacon_)
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

    function beacon() external view returns (address beacon_) {
        assembly {
            beacon_ := sload(BEACON_SLOT)
        }
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    fallback() external payable {
        _delegate(_implementation());
    }

    receive() external payable {
        _delegate(_implementation());
    }

    function _implementation() internal view returns (address implementation_) {
        address beacon_;
        assembly {
            beacon_ := sload(BEACON_SLOT)
        }
        implementation_ = _readImplementation(beacon_);
    }

    function _readImplementation(address beacon_) private view returns (address implementation_) {
        assembly {
            // implementation() selector = 0x5c60da1b
            mstore(0x00, 0x5c60da1b00000000000000000000000000000000000000000000000000000000)
            let ok := staticcall(gas(), beacon_, 0x00, 0x04, 0x00, 0x20)
            if iszero(ok) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
            if lt(returndatasize(), 0x20) { revert(0x00, 0x00) }
            implementation_ := mload(0x00)
        }
    }

    function _delegate(address implementation_) private {
        assembly {
            calldatacopy(0x00, 0x00, calldatasize())
            let ok := delegatecall(gas(), implementation_, 0x00, calldatasize(), 0x00, 0x00)
            returndatacopy(0x00, 0x00, returndatasize())
            switch ok
            case 0 { revert(0x00, returndatasize()) }
            default { return(0x00, returndatasize()) }
        }
    }
}
