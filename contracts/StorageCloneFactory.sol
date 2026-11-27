// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1967BeaconProxy} from "./ERC1967BeaconProxy.sol";

/// @notice CREATE2 factory for optimized StorageV2 beacon clones.
/// @dev One shared beacon upgrades every clone. Owner can be baked into the
///      proxy at deploy time (StorageV2 PROXY_OWNER_SLOT) to avoid a second tx.
contract StorageCloneFactory {
    address public immutable beacon;

    error InvalidBeacon(address beacon_);
    error InvalidOwner(address owner);
    error DeployFailed(bytes32 salt);
    error CloneExists(address clone);

    event CloneDeployed(
        address indexed clone,
        address indexed owner,
        bytes32 indexed salt,
        address beacon
    );

    constructor(address beacon_) {
        if (beacon_ == address(0) || beacon_.code.length == 0) {
            revert InvalidBeacon(beacon_);
        }
        beacon = beacon_;
    }

    /// @notice Predict the CREATE2 address for a clone.
    function predict(address owner, bytes32 salt) public view returns (address) {
        bytes32 initCodeHash = keccak256(_initCode(owner));
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }

    /// @notice Deploy a StorageV2 beacon clone with CREATE2.
    /// @param owner Storage owner EOA written into the proxy (or address(0) to defer).
    /// @param salt CREATE2 salt; include owner/account id offchain for uniqueness.
    function deploy(address owner, bytes32 salt) public payable returns (address clone) {
        clone = _deploy(owner, salt);
    }

    /// @notice Deploy using `keccak256(abi.encode(owner, accountId))` as the salt.
    function deployForAccount(address owner, uint256 accountId)
        external
        payable
        returns (address clone, bytes32 salt)
    {
        salt = keccak256(abi.encode(owner, accountId));
        clone = _deploy(owner, salt);
    }

    function _deploy(address owner, bytes32 salt) private returns (address clone) {
        if (owner != address(0) && owner.code.length != 0) {
            revert InvalidOwner(owner);
        }

        address predicted = predict(owner, salt);
        if (predicted.code.length != 0) {
            revert CloneExists(predicted);
        }

        bytes memory initCode = _initCode(owner);
        assembly {
            clone := create2(callvalue(), add(initCode, 0x20), mload(initCode), salt)
        }
        if (clone == address(0)) {
            revert DeployFailed(salt);
        }

        emit CloneDeployed(clone, owner, salt, beacon);
    }

    function _initCode(address owner) private view returns (bytes memory) {
        return bytes.concat(type(ERC1967BeaconProxy).creationCode, abi.encode(beacon, owner));
    }
}
