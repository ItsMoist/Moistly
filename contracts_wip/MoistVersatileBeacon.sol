// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Standard DCC3-owned beacon for the versatile Moistly proxy stack.
contract MoistVersatileBeacon is UpgradeableBeacon, Ownable2Step {
    error ImplementationCodeHashMismatch(bytes32 expected, bytes32 actual);
    error NativeTransferFailed(address recipient, uint256 amount);
    error OwnershipRenunciationDisabled();
    error UncheckedUpgradeDisabled();

    event NativeReceived(address indexed sender, uint256 amount);
    event NativeWithdrawn(address indexed recipient, uint256 amount);

    constructor(address implementation_, address initialOwner)
        UpgradeableBeacon(implementation_, initialOwner)
    {}

    /// @notice Returns the version of this beacon administration interface.
    function beaconVersion() external pure returns (uint256) {
        return 1;
    }

    /// @notice Returns the runtime bytecode hash of the active implementation.
    function implementationCodeHash() external view returns (bytes32) {
        return implementation().codehash;
    }

    /// @notice Upgrades every attached proxy after verifying the reviewed runtime bytecode hash.
    /// @param newImplementation Contract containing the new proxy logic.
    /// @param expectedRuntimeCodeHash Expected `extcodehash` of `newImplementation`.
    function upgradeToChecked(address newImplementation, bytes32 expectedRuntimeCodeHash)
        external
        onlyOwner
    {
        bytes32 actualRuntimeCodeHash = newImplementation.codehash;
        if (actualRuntimeCodeHash != expectedRuntimeCodeHash) {
            revert ImplementationCodeHashMismatch(expectedRuntimeCodeHash, actualRuntimeCodeHash);
        }
        super.upgradeTo(newImplementation);
    }

    /// @dev All upgrades must commit to the reviewed implementation runtime hash.
    function upgradeTo(address) public pure override {
        revert UncheckedUpgradeDisabled();
    }

    /// @notice Begins a two-step transfer of beacon upgrade authority.
    /// @param newOwner Address that must explicitly accept ownership.
    function transferOwnership(address newOwner)
        public
        override(Ownable, Ownable2Step)
        onlyOwner
    {
        Ownable2Step.transferOwnership(newOwner);
    }

    /// @notice Withdraws native currency accidentally or intentionally held by the beacon.
    function withdrawNative(address payable recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert OwnableInvalidOwner(address(0));
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert NativeTransferFailed(recipient, amount);
        emit NativeWithdrawn(recipient, amount);
    }

    /// @notice Always reverts so beacon upgrade authority cannot be permanently abandoned.
    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function _transferOwnership(address newOwner)
        internal
        override(Ownable, Ownable2Step)
    {
        Ownable2Step._transferOwnership(newOwner);
    }

    /// @notice Accepts native currency and records its sender and amount.
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
