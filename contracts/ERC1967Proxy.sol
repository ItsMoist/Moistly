// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "lib/forge-std/src/console.sol";
/// @notice Minimal ERC-1967 proxy for deterministic StorageV2 deployments.
contract ERC1967Proxy {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal owner;

    error InitializerDelegateCallBlocked();

    constructor(uint256 accountNumber, address implementation_, bytes memory data) payable {
        owner = msg.sender;
        console.log("Owner: %s", owner);
        console.log("Implementation: %s", implementation_);
        console.log("Account Number: %s", accountNumber);
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
        assembly {
            let offset := mload(0x40)
            let impl := sload(IMPLEMENTATION_SLOT)
            let size := calldatasize()
            mstore(offset, size)
            call(gas(), impl, callvalue(), 0, calldatasize(), 0, 0)
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
   
    receive() external payable {
        assembly {
            let impl := sload(IMPLEMENTATION_SLOT)
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
