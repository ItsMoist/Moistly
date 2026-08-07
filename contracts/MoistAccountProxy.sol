// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC-1967 implementation proxy intended for deterministic account deployments.
/// @dev The implementation slot is initialized exactly once in the constructor. Upgrade authority,
///      if desired, belongs in the implementation logic rather than in this proxy shell.
contract MoistAccountProxy {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error InvalidImplementation();
    error InitializationFailed(bytes reason);

    constructor(address implementation_, bytes memory initData) payable {
        if (implementation_ == address(0) || implementation_.code.length == 0) {
            revert InvalidImplementation();
        }

        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }

        if (initData.length != 0) {
            (bool ok, bytes memory reason) = implementation_.delegatecall(initData);
            if (!ok) revert InitializationFailed(reason);
        }
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

    function _delegate() private {
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
