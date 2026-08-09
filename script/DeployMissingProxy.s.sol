// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IDeterministicDeployFactory {
    function deploy(bytes32 salt, bytes calldata creationCode)
        external
        payable
        returns (address deployed);
}

/// @notice Guarded recovery deployment for the currently empty proxy target.
/// @dev The script deliberately requires the factory to return the exact target address.
///      Forge simulates the full script before broadcasting, so a wrong salt/init-code/factory
///      causes the simulation to revert before any transaction is sent.
contract DeployMissingProxy is Script {
    address internal constant TARGET = 0x24be9E13Dc977E8137d60870Cec1C2B692d52526;

    function run() external returns (address deployed) {
        address factory = vm.envAddress("MISSING_PROXY_FACTORY");
        bytes32 salt = vm.envBytes32("MISSING_PROXY_SALT");
        bytes memory creationCode = vm.envBytes("MISSING_PROXY_CREATION_CODE");
        uint256 value = vm.envOr("MISSING_PROXY_VALUE", uint256(0));

        require(TARGET.code.length == 0, "target already has code");
        require(factory.code.length != 0, "factory has no code");
        require(creationCode.length != 0, "creation code empty");

        vm.startBroadcast();
        deployed = IDeterministicDeployFactory(factory).deploy{value: value}(salt, creationCode);
        vm.stopBroadcast();

        require(deployed == TARGET, "factory/salt/init-code do not resolve target");
        require(TARGET.code.length != 0, "deployment returned target but code is empty");

        console2.log("Recovered proxy deployed at", deployed);
    }
}
