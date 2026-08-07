// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice ERC-4337 v0.7 PackedUserOperation shape used by EntryPoint.
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

interface IMoist7702Guard {
    function beforeExecute(address account, address to, uint256 value, bytes calldata data) external;
    function afterExecute(address account, address to, uint256 value, bytes calldata data, bool success) external;
}

/// @notice EIP-7702 delegation target with ERC-4337 v0.7 validation and optional execution guard.
/// @dev Deploy this implementation at the same deterministic address on every chain, then authorize
///      each EOA to delegate to that address using EIP-7702. Mutable state lives in the delegating
///      EOA because calls execute in the EOA storage context.
contract Moist7702Account {
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    bytes4 public constant ERC1271_MAGICVALUE = 0x1626ba7e;
    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    /// @custom:storage-location erc7201:moistly.storage.Moist7702Account
    struct AccountStorage {
        address guard;
        uint64 guardEpoch;
    }

    bytes32 private constant ACCOUNT_STORAGE_SLOT =
        0x0d7e280e77f5d4cd20930b37d7970042de7bdbedcb81ad0b22398da6a997e400;

    error Unauthorized(address caller);
    error InvalidTarget();
    error ExecutionFailed(bytes reason);
    error LengthMismatch();

    event GuardUpdated(address indexed previousGuard, address indexed newGuard, uint64 epoch);
    event Executed(address indexed target, uint256 value, bytes4 indexed selector);

    modifier onlySelfOrEntryPoint() {
        if (msg.sender != address(this) && msg.sender != ENTRY_POINT_V07) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert Unauthorized(msg.sender);
        _;
    }

    receive() external payable {}

    /// @notice Returns the configured EntryPoint.
    function entryPoint() external pure returns (address) {
        return ENTRY_POINT_V07;
    }

    /// @notice Returns the optional execution guard stored on the delegated EOA.
    function guard() external view returns (address) {
        return _accountStorage().guard;
    }

    /// @notice Set or clear the execution guard. The EOA must call itself to authorize this action.
    function setGuard(address newGuard) external onlySelf {
        AccountStorage storage state = _accountStorage();
        address previous = state.guard;
        unchecked {
            ++state.guardEpoch;
        }
        state.guard = newGuard;
        emit GuardUpdated(previous, newGuard, state.guardEpoch);
    }

    /// @notice Execute one call from the delegated EOA.
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        onlySelfOrEntryPoint
        returns (bytes memory result)
    {
        result = _execute(target, value, data);
    }

    /// @notice Execute multiple calls atomically from the delegated EOA.
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        payable
        onlySelfOrEntryPoint
        returns (bytes[] memory results)
    {
        uint256 length = targets.length;
        if (length != values.length || length != data.length) revert LengthMismatch();

        results = new bytes[](length);
        for (uint256 i; i < length; ++i) {
            results[i] = _execute(targets[i], values[i], data[i]);
        }
    }

    /// @notice ERC-4337 account validation. Signature must recover to the delegated EOA address.
    /// @dev Returns SIG_VALIDATION_FAILED instead of reverting for invalid signatures.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        if (msg.sender != ENTRY_POINT_V07) revert Unauthorized(msg.sender);
        if (userOp.sender != address(this)) return SIG_VALIDATION_FAILED;

        bool valid = _isValidSigner(userOpHash, userOp.signature);
        if (!valid) return SIG_VALIDATION_FAILED;

        if (missingAccountFunds != 0) {
            (bool funded,) = payable(msg.sender).call{value: missingAccountFunds}("");
            funded;
        }
        return 0;
    }

    /// @notice ERC-1271 validation against the delegated EOA key.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return _isValidSigner(hash, signature) ? ERC1271_MAGICVALUE : bytes4(0xffffffff);
    }

    function _execute(address target, uint256 value, bytes calldata data) private returns (bytes memory result) {
        if (target == address(0)) revert InvalidTarget();

        address configuredGuard = _accountStorage().guard;
        if (configuredGuard != address(0)) {
            IMoist7702Guard(configuredGuard).beforeExecute(address(this), target, value, data);
        }

        (bool ok, bytes memory returnData) = target.call{value: value}(data);

        if (configuredGuard != address(0)) {
            IMoist7702Guard(configuredGuard).afterExecute(address(this), target, value, data, ok);
        }

        if (!ok) revert ExecutionFailed(returnData);

        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        emit Executed(target, value, selector);
        return returnData;
    }

    function _isValidSigner(bytes32 hash, bytes calldata signature) private view returns (bool) {
        address signer = _recover(hash, signature);
        if (signer == address(this)) return true;

        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        return _recover(ethSignedHash, signature) == address(this);
    }

    function _recover(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        if (uint256(s) > SECP256K1N_DIV_2) return address(0);
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        signer = ecrecover(digest, v, r, s);
    }

    function _accountStorage() private pure returns (AccountStorage storage state) {
        bytes32 slot = ACCOUNT_STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }
}
