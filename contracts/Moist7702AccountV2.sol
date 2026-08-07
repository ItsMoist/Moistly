// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct PackedUserOperationV2 {
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

struct CCIPTokenAmount {
    address token;
    uint256 amount;
}

struct Any2EVMMessage {
    bytes32 messageId;
    uint64 sourceChainSelector;
    bytes sender;
    bytes data;
    CCIPTokenAmount[] destTokenAmounts;
}

interface IERC20ApproveV2 {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IMoist7702GuardV2 {
    function beforeExecute(address account, address to, uint256 value, bytes calldata data) external;
    function afterExecute(address account, address to, uint256 value, bytes calldata data, bool success) external;
}

/// @notice Canonical DCC3 account implementation for EIP-7702 delegation.
/// @dev DCC3 is the account identity. EIP-7702 is only the delegation mechanism.
///      Cross-chain protocols MUST resolve/route to verifyingAccount(), never directly to a venue.
contract Moist7702AccountV2 {
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    bytes4 public constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 public constant ERC173_INTERFACE_ID = 0x7f5828d0;
    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    bytes4 private constant CCTP_DEPOSIT_FOR_BURN_SELECTOR =
        bytes4(keccak256("depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)"));
    bytes4 private constant CCTP_RECEIVE_MESSAGE_SELECTOR = bytes4(keccak256("receiveMessage(bytes,bytes)"));

    struct AccountStorage {
        address owner;
        address guard;
        address verifyingAccount;
        address ccipRouter;
        bytes32 factorySalt;
        uint64 guardEpoch;
        uint64 cctpBurnCount;
        uint64 cctpMintCount;
        uint64 ccipReceiveCount;
        bool initialized;
        mapping(bytes32 => bool) cctpFinalized;
        mapping(uint64 => bytes32) trustedCCIPSender;
        mapping(bytes32 => bool) ccipReceived;
    }

    bytes32 public constant ACCOUNT_STORAGE_SLOT = keccak256("moistly.storage.Moist7702Account.v2");
    bytes32 public constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error Unauthorized(address caller);
    error InvalidTarget();
    error InvalidOwner();
    error AlreadyInitialized();
    error ExecutionFailed(bytes reason);
    error TokenApprovalFailed(address token, address spender, uint256 amount);
    error InvalidCrossChainRecipient(address supplied, address expected);
    error InvalidCCIPRouter(address caller, address expected);
    error InvalidCCIPSender(uint64 selector, bytes32 sender, bytes32 expected);
    error MessageAlreadyProcessed(bytes32 messageId);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FactoryIdentityUpdated(bytes32 indexed factorySalt, address indexed verifyingAccount);
    event GuardUpdated(address indexed previousGuard, address indexed newGuard, uint64 epoch);
    event CCIPRouterUpdated(address indexed previousRouter, address indexed newRouter);
    event CCIPTrustedSenderUpdated(uint64 indexed sourceChainSelector, bytes32 indexed sender);
    event CCIPMessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, bytes32 indexed sender);
    event CCTPBurnSubmitted(address indexed tokenMessenger, address indexed burnToken, uint256 amount, uint32 destinationDomain, bytes32 indexed mintRecipient, uint64 localBurnIndex);
    event CCTPMintFinalized(address indexed messageTransmitter, bytes32 indexed messageHash, uint64 localMintIndex);
    event Executed(address indexed target, uint256 value, bytes4 indexed selector);

    modifier onlySelfOrEntryPoint() {
        if (msg.sender != address(this) && msg.sender != ENTRY_POINT_V07) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyOwnerOrSelf() {
        if (msg.sender != owner() && msg.sender != address(this)) revert Unauthorized(msg.sender);
        _;
    }

    receive() external payable {}

    function initializeAccount(address initialOwner, bytes32 factorySalt_, address verifyingAccount_) external onlySelfOrEntryPoint {
        AccountStorage storage s = _state();
        if (s.initialized) revert AlreadyInitialized();
        if (initialOwner == address(0)) initialOwner = address(this);
        if (verifyingAccount_ == address(0)) verifyingAccount_ = address(this);
        s.initialized = true;
        s.owner = initialOwner;
        s.factorySalt = factorySalt_;
        s.verifyingAccount = verifyingAccount_;
        emit OwnershipTransferred(address(0), initialOwner);
        emit FactoryIdentityUpdated(factorySalt_, verifyingAccount_);
    }

    // EIP-173 ownership domain.
    function owner() public view returns (address currentOwner) {
        currentOwner = _state().owner;
        if (currentOwner == address(0)) currentOwner = address(this);
    }

    function transferOwnership(address newOwner) external onlyOwnerOrSelf {
        if (newOwner == address(0)) revert InvalidOwner();
        AccountStorage storage s = _state();
        address previous = owner();
        s.owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID || interfaceId == ERC173_INTERFACE_ID;
    }

    function verifyingAccount() public view returns (address account) {
        account = _state().verifyingAccount;
        if (account == address(0)) account = address(this);
    }

    function factorySalt() external view returns (bytes32) { return _state().factorySalt; }
    function guard() external view returns (address) { return _state().guard; }
    function ccipRouter() external view returns (address) { return _state().ccipRouter; }
    function entryPoint() external pure returns (address) { return ENTRY_POINT_V07; }
    function storageSlot() external pure returns (bytes32) { return ACCOUNT_STORAGE_SLOT; }

    function setFactoryIdentity(bytes32 salt, address account) external onlyOwnerOrSelf {
        if (account == address(0)) revert InvalidTarget();
        _state().factorySalt = salt;
        _state().verifyingAccount = account;
        emit FactoryIdentityUpdated(salt, account);
    }

    function setGuard(address newGuard) external onlyOwnerOrSelf {
        AccountStorage storage s = _state();
        address previous = s.guard;
        unchecked { ++s.guardEpoch; }
        s.guard = newGuard;
        emit GuardUpdated(previous, newGuard, s.guardEpoch);
    }

    function setCCIPRouter(address router) external onlyOwnerOrSelf {
        address previous = _state().ccipRouter;
        _state().ccipRouter = router;
        emit CCIPRouterUpdated(previous, router);
    }

    /// @notice Store a canonical 20-byte EVM account as bytes32(uint160(account)).
    function setTrustedCCIPSender(uint64 sourceChainSelector, address sourceAccount) external onlyOwnerOrSelf {
        if (sourceAccount == address(0)) revert InvalidTarget();
        bytes32 sender = bytes32(uint256(uint160(sourceAccount)));
        _state().trustedCCIPSender[sourceChainSelector] = sender;
        emit CCIPTrustedSenderUpdated(sourceChainSelector, sender);
    }

    function trustedCCIPSender(uint64 sourceChainSelector) external view returns (bytes32) {
        return _state().trustedCCIPSender[sourceChainSelector];
    }

    /// @notice Chainlink CCIP receiver entrypoint. Tokens are delivered to DCC3/verifyingAccount itself.
    /// @dev The configured Router is the only permitted caller; sender is bound per source selector.
    function ccipReceive(Any2EVMMessage calldata message) external {
        AccountStorage storage s = _state();
        if (msg.sender != s.ccipRouter) revert InvalidCCIPRouter(msg.sender, s.ccipRouter);
        if (s.ccipReceived[message.messageId]) revert MessageAlreadyProcessed(message.messageId);
        if (message.sender.length != 32) revert InvalidTarget();
        bytes32 sender = abi.decode(message.sender, (bytes32));
        bytes32 expected = s.trustedCCIPSender[message.sourceChainSelector];
        if (expected == bytes32(0) || sender != expected) {
            revert InvalidCCIPSender(message.sourceChainSelector, sender, expected);
        }
        s.ccipReceived[message.messageId] = true;
        unchecked { ++s.ccipReceiveCount; }
        emit CCIPMessageReceived(message.messageId, message.sourceChainSelector, sender);
    }

    function ccipMessageReceived(bytes32 messageId) external view returns (bool) { return _state().ccipReceived[messageId]; }

    /// @notice CCTP V2 burn locked to the configured verifying account.
    function cctpBurnToVerifyingAccount(
        address tokenMessenger,
        address burnToken,
        uint256 amount,
        uint32 destinationDomain,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlySelfOrEntryPoint returns (bytes memory returnData) {
        if (tokenMessenger == address(0) || burnToken == address(0)) revert InvalidTarget();
        bytes32 recipient = bytes32(uint256(uint160(verifyingAccount())));

        (bool approved, bytes memory approvalData) = burnToken.call(
            abi.encodeWithSelector(IERC20ApproveV2.approve.selector, tokenMessenger, amount)
        );
        if (!approved || (approvalData.length != 0 && !abi.decode(approvalData, (bool)))) {
            revert TokenApprovalFailed(burnToken, tokenMessenger, amount);
        }

        bytes memory burnData = abi.encodeWithSelector(
            CCTP_DEPOSIT_FOR_BURN_SELECTOR,
            amount,
            destinationDomain,
            recipient,
            burnToken,
            recipient,
            maxFee,
            minFinalityThreshold
        );
        returnData = _execute(tokenMessenger, 0, burnData);
        AccountStorage storage s = _state();
        unchecked { ++s.cctpBurnCount; }
        emit CCTPBurnSubmitted(tokenMessenger, burnToken, amount, destinationDomain, recipient, s.cctpBurnCount);
    }

    /// @notice Destination CCTP V2 attestation finalization. Circle mints to the message's recipient,
    ///         which source-side policy constrains to verifyingAccount().
    function cctpFinalizeMint(address messageTransmitter, bytes calldata message, bytes calldata attestation)
        external onlySelfOrEntryPoint returns (bytes memory returnData)
    {
        if (messageTransmitter == address(0)) revert InvalidTarget();
        bytes32 messageHash = keccak256(message);
        AccountStorage storage s = _state();
        if (s.cctpFinalized[messageHash]) revert MessageAlreadyProcessed(messageHash);
        returnData = _execute(messageTransmitter, 0, abi.encodeWithSelector(CCTP_RECEIVE_MESSAGE_SELECTOR, message, attestation));
        s.cctpFinalized[messageHash] = true;
        unchecked { ++s.cctpMintCount; }
        emit CCTPMintFinalized(messageTransmitter, messageHash, s.cctpMintCount);
    }

    /// @notice Lighter and other venues are downstream calls only. No bridge function targets them directly.
    function execute(address target, uint256 value, bytes calldata data)
        external payable onlySelfOrEntryPoint returns (bytes memory result)
    {
        return _execute(target, value, data);
    }

    function validateUserOp(PackedUserOperationV2 calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external returns (uint256)
    {
        if (msg.sender != ENTRY_POINT_V07) revert Unauthorized(msg.sender);
        if (userOp.sender != address(this) || !_isValidSigner(userOpHash, userOp.signature)) return SIG_VALIDATION_FAILED;
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
        address configuredGuard = _state().guard;
        if (configuredGuard != address(0)) {
            IMoist7702GuardV2(configuredGuard).beforeExecute(address(this), target, value, data);
        }
        (bool ok, bytes memory returned) = target.call{value: value}(data);
        if (configuredGuard != address(0)) {
            IMoist7702GuardV2(configuredGuard).afterExecute(address(this), target, value, data, ok);
        }
        if (!ok) revert ExecutionFailed(returned);
        bytes4 selector;
        if (data.length >= 4) assembly { selector := mload(add(data, 0x20)) }
        emit Executed(target, value, selector);
        return returned;
    }

    function _isValidSigner(bytes32 hash, bytes calldata signature) private view returns (bool) {
        address expected = owner();
        address signer = _recover(hash, signature);
        if (signer == expected) return true;
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        return _recover(ethSignedHash, signature) == expected;
    }

    function _recover(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != 65) return address(0);
        bytes32 r; bytes32 s; uint8 v;
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

    function _state() private pure returns (AccountStorage storage s) {
        bytes32 slot = ACCOUNT_STORAGE_SLOT;
        assembly { s.slot := slot }
    }
}
