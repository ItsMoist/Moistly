
/** 
 *  SourceUnit: /Users/bnelligan/DAPP/Moistly/contracts/ERC1967Proxy.sol
*/

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC-1967 proxy for deterministic StorageV2 deployments.
contract ERC1967Proxy {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error InitializerDelegateCallBlocked();

    constructor(address implementation_, bytes memory data) payable {
        require(implementation_.code.length != 0, "implementation has no code");
        if (data.length != 0) {
            revert InitializerDelegateCallBlocked();
        }

        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }
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
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

