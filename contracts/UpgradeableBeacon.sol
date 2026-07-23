// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "lib/forge-std/src/console.sol";
import {ERC1967Proxy} from "../contracts/ERC1967Proxy.sol";
/// @notice Minimal owner-controlled beacon for deterministic BeaconProxy deployments.

interface IMoistBeacon {
    
}
contract UpgradeableBeacon is ERC1967Proxy {
    address private _implementation;
    // msg.sender will still be set even though the proxy is not initialized.
    address private _owner = msg.sender;
    error InvalidImplementation(address implementation);
    error NotOwner(address caller);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed implementation);
    event BeaconUpgraded(address indexed beacon);
    event AdminChanged(address previousAdmin, address newAdmin);
    event ReceivedEther(address indexed from, uint256 value);
    
    
    constructor(address implementation_, address owner_) {
        if (implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }
        if (owner_ == address(0)|| owner_ == address(1)) {
            revert NotOwner(address(0));
        }
        

        _implementation = implementation_;
        _owner = owner_;

        emit OwnershipTransferred(address(0), owner_);
        emit Upgraded(implementation_);
    }

    function implementation() external view returns (address) {
        return _implementation;
    }


    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0) || newOwner == address(1)) {
            revert NotOwner(address(0));
        }
        console.log("Transferring ownership from %s to %s", _owner, newOwner);
        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        if (newImplementation.code.length == 0 || newImplementation == address(0) || newImplementation == address(1)) {
            console.log("Invalid implementation: %s", newImplementation);
            emit InvalidImplementation(newImplementation);
            revert InvalidImplementation(newImplementation);
        }
        _implementation = newImplementation;
        emit BeaconUpgraded(newImplementation);
    }

    receive() external payable {
        // Allow the beacon to receive Ether
        emit ReceivedEther(msg.sender, msg.value);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }
}
