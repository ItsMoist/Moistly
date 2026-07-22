// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface ISafeTransactionGuard is IERC165 {
    enum Operation {
        Call,
        DelegateCall
    }

    function checkTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures,
        address msgSender
    ) external;

    function checkAfterExecution(bytes32 txHash, bool success) external;
}

/// @notice Conservative Safe transaction guard for multisig and AA-submitted Safe transactions.
/// @dev The guard intentionally leaves ordinary calls and ERC20 transfers available, but blocks
///      delegatecalls, Safe self-reconfiguration, EntryPoint calls, contract creation, and Safe
///      refund fields that can be abused by relayers/bundlers.
contract MoistSafeGuard is ISafeTransactionGuard {
    address public immutable safe;

    address private constant ENTRY_POINT_V06 = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address private constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    bytes4 private constant ADD_OWNER_WITH_THRESHOLD = 0x0d582f13;
    bytes4 private constant CHANGE_THRESHOLD = 0x694e80c3;
    bytes4 private constant DISABLE_MODULE = 0xe009cfde;
    bytes4 private constant ENABLE_MODULE = 0x610b5925;
    bytes4 private constant REMOVE_OWNER = 0xf8dc5dd9;
    bytes4 private constant SET_FALLBACK_HANDLER = 0xf08a0323;
    bytes4 private constant SET_GUARD = 0xe19a9dd9;
    bytes4 private constant SET_MODULE_GUARD = 0x85e1d4e5;
    bytes4 private constant SETUP = 0xb63e800d;
    bytes4 private constant SWAP_OWNER = 0xe318b52b;

    error InvalidAddress();
    error NotSafe(address caller);
    error DelegateCallBlocked(address target);
    error ContractCreationBlocked();
    error EntryPointCallBlocked(address entryPoint);
    error RefundBlocked(uint256 gasPrice, address gasToken, address refundReceiver);
    error SafeConfigurationBlocked(bytes4 selector);

    constructor(address safe_) {
        if (safe_ == address(0)) {
            revert InvalidAddress();
        }

        safe = safe_;
    }

    function checkTransaction(
        address to,
        uint256,
        bytes calldata data,
        Operation operation,
        uint256,
        uint256,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata,
        address
    ) external view {
        if (msg.sender != safe) {
            revert NotSafe(msg.sender);
        }
        if (operation == Operation.DelegateCall) {
            revert DelegateCallBlocked(to);
        }
        if (to == address(0) && data.length != 0) {
            revert ContractCreationBlocked();
        }
        if (to == ENTRY_POINT_V06 || to == ENTRY_POINT_V07) {
            revert EntryPointCallBlocked(to);
        }
        if (gasPrice != 0 || gasToken != address(0) || refundReceiver != address(0)) {
            revert RefundBlocked(gasPrice, gasToken, refundReceiver);
        }
        if (to == safe) {
            bytes4 selector = _selector(data);
            if (_isBlockedSafeConfigurationSelector(selector)) {
                revert SafeConfigurationBlocked(selector);
            }
        }
    }

    function checkAfterExecution(bytes32, bool) external view {
        if (msg.sender != safe) {
            revert NotSafe(msg.sender);
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISafeTransactionGuard).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _selector(bytes calldata data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }
        return bytes4(data[:4]);
    }

    function _isBlockedSafeConfigurationSelector(bytes4 selector) internal pure returns (bool) {
        return selector == ADD_OWNER_WITH_THRESHOLD || selector == CHANGE_THRESHOLD || selector == DISABLE_MODULE
            || selector == ENABLE_MODULE || selector == REMOVE_OWNER || selector == SET_FALLBACK_HANDLER || selector == SET_GUARD
            || selector == SET_MODULE_GUARD || selector == SETUP || selector == SWAP_OWNER;
    }
}
