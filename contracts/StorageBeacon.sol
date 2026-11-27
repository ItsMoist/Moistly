// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal owner-controlled beacon for StorageV2 clones.
/// @dev Prefer this over the unfinished MoistBeacon for Elysium / new deploys.
contract StorageBeacon {
    address private _implementation;
    address private _owner;

    error InvalidImplementation(address implementation);
    error NotOwner(address caller);
    error InvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed implementation);

    constructor(address implementation_, address owner_) {
        if (implementation_ == address(0) || implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }
        if (owner_ == address(0)) {
            revert InvalidOwner(owner_);
        }
        _implementation = implementation_;
        _owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
        emit Upgraded(implementation_);
    }

    function implementation() external view returns (address) {
        return _implementation;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != _owner) revert NotOwner(msg.sender);
        if (newOwner == address(0)) revert InvalidOwner(newOwner);
        address previous = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    function upgradeTo(address newImplementation) external {
        if (msg.sender != _owner) revert NotOwner(msg.sender);
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidImplementation(newImplementation);
        }
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}
