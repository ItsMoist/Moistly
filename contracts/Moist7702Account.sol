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

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice EIP-7702 delegation target with ERC-4337 v0.7 validation, ERC-173 ownership,
///         optional execution guard, and CCTP V2 burn/mint helpers.
/// @dev The account address and the EIP-7702 mechanism are distinct concepts. An account may use
///      EIP-7702 as one execution/authentication mechanism without changing its identity.
contract Moist7702Account {
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    bytes4 public constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 public constant ERC173_INTERFACE_ID = 0x7f5828d0;
    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    bytes4 private constant CCTP_DEPOSIT_FOR_BURN_SELECTOR =
        bytes4(keccak256("depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)"));
    bytes4 private constant CCTP_RECEIVE_MESSAGE_SELECTOR =
        bytes4(keccak256("receiveMessage(bytes,bytes)"));

    struct AccountStorage {
        // ERC-173 ownership/control domain. Zero means the delegated account self-owns by default.
        address owner;
        address guard;
        uint64 guardEpoch;
        uint64 cctpBurnCount;
        uint64 cctpMintCount;
        mapping(bytes32 messageHash => bool finalized) cctpFinalized;
    }

    // Dedicated namespaced slot. Do not reorder delegated-account state into ordinary slots.
    bytes32 private constant ACCOUNT_STORAGE_SLOT = keccak256("moistly.storage.Moist7702Account.v1");

    error Unauthorized(address caller);
    error InvalidTarget();
    error ExecutionFailed(bytes reason);
    error LengthMismatch();
    error TokenApprovalFailed(address token, address spender, uint256 amount);
    error CCTPMessageAlreadyFinalized(bytes32 messageHash);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event GuardUpdated(address indexed previousGuard, address indexed newGuard, uint64 epoch);
    event Executed(address indexed target, uint256 value, bytes4 indexed selector);
    event CCTPBurnSubmitted(
        address indexed tokenMessenger,
        address indexed burnToken,
        uint256 amount,
        uint32 destinationDomain,
        bytes32 indexed mintRecipient,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        uint64 localBurnIndex
    );
    event CCTPMintFinalized(
        address indexed messageTransmitter,
        bytes32 indexed messageHash,
        uint64 localMintIndex
    );

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

    modifier onlyOwner() {
        if (msg.sender != owner()) revert Unauthorized(msg.sender);
        _;
    }

    receive() external payable {}

    function entryPoint() external pure returns (address) {
        return ENTRY_POINT_V07;
    }

    /// @notice ERC-173 owner. Until explicitly transferred, a delegated account is self-owned.
    function owner() public view returns (address currentOwner) {
        currentOwner = _accountStorage().owner;
        if (currentOwner == address(0)) currentOwner = address(this);
    }

    /// @notice ERC-173 ownership transfer. Ownership is independent from the EIP-7702 signer key.
    /// @dev Passing address(0) renounces the ERC-173 control domain as permitted by ERC-173.
    function transferOwnership(address newOwner) external onlyOwner {
        AccountStorage storage state = _accountStorage();
        address previousOwner = owner();
        state.owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice ERC-165 discovery for ERC-165 and ERC-173.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID || interfaceId == ERC173_INTERFACE_ID;
    }

    function guard() external view returns (address) {
        return _accountStorage().guard;
    }

    function cctpBurnCount() external view returns (uint64) {
        return _accountStorage().cctpBurnCount;
    }

    function cctpMintCount() external view returns (uint64) {
        return _accountStorage().cctpMintCount;
    }

    function cctpMessageFinalized(bytes32 messageHash) external view returns (bool) {
        return _accountStorage().cctpFinalized[messageHash];
    }

    /// @notice Set or clear the execution guard. Execution authority remains separate from ERC-173 ownership.
    function setGuard(address newGuard) external onlySelf {
        AccountStorage storage state = _accountStorage();
        address previous = state.guard;
        unchecked {
            ++state.guardEpoch;
        }
        state.guard = newGuard;
        emit GuardUpdated(previous, newGuard, state.guardEpoch);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        onlySelfOrEntryPoint
        returns (bytes memory result)
    {
        result = _execute(target, value, data);
    }

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

    function cctpBurn(
        address tokenMessenger,
        address burnToken,
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlySelfOrEntryPoint returns (bytes memory returnData) {
        if (tokenMessenger == address(0) || burnToken == address(0)) revert InvalidTarget();

        (bool approved, bytes memory approvalData) = burnToken.call(
            abi.encodeWithSelector(IERC20Approve.approve.selector, tokenMessenger, amount)
        );
        if (!approved || (approvalData.length != 0 && !abi.decode(approvalData, (bool)))) {
            revert TokenApprovalFailed(burnToken, tokenMessenger, amount);
        }

        bytes memory burnData = abi.encodeWithSelector(
            CCTP_DEPOSIT_FOR_BURN_SELECTOR,
            amount,
            destinationDomain,
            mintRecipient,
            burnToken,
            destinationCaller,
            maxFee,
            minFinalityThreshold
        );
        returnData = _execute(tokenMessenger, 0, burnData);

        AccountStorage storage state = _accountStorage();
        unchecked {
            ++state.cctpBurnCount;
        }
        emit CCTPBurnSubmitted(
            tokenMessenger,
            burnToken,
            amount,
            destinationDomain,
            mintRecipient,
            destinationCaller,
            maxFee,
            minFinalityThreshold,
            state.cctpBurnCount
        );
    }

    function cctpFinalizeMint(address messageTransmitter, bytes calldata message, bytes calldata attestation)
        external
        onlySelfOrEntryPoint
        returns (bytes memory returnData)
    {
        if (messageTransmitter == address(0)) revert InvalidTarget();

        bytes32 messageHash = keccak256(message);
        AccountStorage storage state = _accountStorage();
        if (state.cctpFinalized[messageHash]) revert CCTPMessageAlreadyFinalized(messageHash);

        bytes memory receiveData = abi.encodeWithSelector(CCTP_RECEIVE_MESSAGE_SELECTOR, message, attestation);
        returnData = _execute(messageTransmitter, 0, receiveData);

        state.cctpFinalized[messageHash] = true;
        unchecked {
            ++state.cctpMintCount;
        }
        emit CCTPMintFinalized(messageTransmitter, messageHash, state.cctpMintCount);
    }

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

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return _isValidSigner(hash, signature) ? ERC1271_MAGICVALUE : bytes4(0xffffffff);
    }

    function _execute(address target, uint256 value, bytes memory data) private returns (bytes memory result) {
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

        bytes4 selector;
        if (data.length >= 4) {
            assembly {
                selector := mload(add(data, 0x20))
            }
        }
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
