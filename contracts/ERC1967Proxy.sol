// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC-1967 proxy for deterministic deployments.
/// @dev Keeps proxy state exclusively in ERC-1967 slots to avoid colliding with implementation storage.
contract ERC1967Proxy {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error InvalidImplementation(address implementation);
    error InitializerDelegateCallBlocked();

    event Upgraded(address indexed implementation);
    event ProxyDeployed(
        uint256 indexed accountNumber,
        address indexed deployer,
        address indexed implementation
    );

    constructor(uint256 accountNumber, address implementation_, bytes memory data) payable {
        if (implementation_.code.length == 0) {
            revert InvalidImplementation(implementation_);
        }
        if (data.length != 0) {
            // Initialization must be performed explicitly after deployment until
            // initializer allow-listing / validation is added.
            revert InitializerDelegateCallBlocked();
        }

        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }

        emit Upgraded(implementation_);
        emit ProxyDeployed(accountNumber, msg.sender, implementation_);
    }

    function implementation() external view returns (address impl) {
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        assembly {
            let impl := sload(IMPLEMENTATION_SLOT)

            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
