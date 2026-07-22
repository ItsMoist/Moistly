// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMoistResolver {
    function resolve(bytes4 selector) external view returns (address destination);
}

/// @notice Upgradeable, owner-operated execution logic for a MoistBeaconProxy.
/// @dev Uses namespaced storage so future implementations can add state safely.
contract MoistExecutor {
    using SafeERC20 for IERC20;

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /// @custom:storage-location erc7201:moistly.storage.MoistExecutor
    struct ExecutorStorage {
        address owner;
        address pendingOwner;
        mapping(address => bool) operators;
        bool initialized;
        uint256 entered;
        mapping(address => uint256) nonces;
        address resolver;
    }

    bytes32 private constant EXECUTOR_STORAGE_SLOT =
        0xd59159ce251683d27fc4f7af65c2f44c48681c706b5c9c8be4137e4e49962000;
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
    );
    bytes32 private constant EXECUTE_TYPEHASH = keccak256(
        "Execute(address signer,address target,uint256 value,bytes32 dataHash,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant NAME_HASH = keccak256("MoistExecutor");
    bytes32 private constant VERSION_HASH = keccak256("1");
    bytes32 public constant DOMAIN_SALT = keccak256("moistly.executor.eip712.v1");

    error AlreadyInitialized();
    error InvalidAddress();
    error Unauthorized(address caller);
    error ReentrantCall();
    error CallFailed(uint256 index, address target, bytes reason);
    error SignatureExpired(uint256 deadline);
    error InvalidNonce(address signer, uint256 expected, uint256 supplied);
    error InvalidSignature(address signer);

    event Initialized(address indexed owner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OperatorUpdated(address indexed operator, bool authorized);
    event CallExecuted(uint256 indexed index, address indexed target, uint256 value, bytes result);
    event NativeReceived(address indexed sender, uint256 amount);
    event SignedCallExecuted(address indexed signer, address indexed relayer, uint256 indexed nonce);
    event ResolverUpdated(address indexed previousResolver, address indexed newResolver);

    constructor() {
        _executorStorage().initialized = true;
    }

    modifier onlyOwner() {
        if (msg.sender != _executorStorage().owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyAuthorized() {
        ExecutorStorage storage state = _executorStorage();
        if (msg.sender != state.owner && !state.operators[msg.sender]) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier nonReentrant() {
        ExecutorStorage storage state = _executorStorage();
        if (state.entered == 2) revert ReentrantCall();
        state.entered = 2;
        _;
        state.entered = 1;
    }

    /// @notice Initializes proxy storage and assigns its first owner.
    /// @dev Must be supplied atomically to the proxy constructor in production.
    function initialize(address initialOwner) external {
        ExecutorStorage storage state = _executorStorage();
        if (state.initialized) revert AlreadyInitialized();
        if (initialOwner == address(0)) revert InvalidAddress();

        state.initialized = true;
        state.entered = 1;
        state.owner = initialOwner;
        emit Initialized(initialOwner);
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Returns the address with administrative and direct execution authority.
    function owner() external view returns (address) {
        return _executorStorage().owner;
    }

    /// @notice Returns the address nominated to accept ownership.
    function pendingOwner() external view returns (address) {
        return _executorStorage().pendingOwner;
    }

    /// @notice Reports whether an address has delegated execution authority.
    function isOperator(address account) external view returns (bool) {
        return _executorStorage().operators[account];
    }

    /// @notice Returns the resolver used by selector-routed execution.
    function resolver() external view returns (address) {
        return _executorStorage().resolver;
    }

    /// @notice Returns the next valid signed-execution nonce for a signer.
    function nonces(address signer) external view returns (uint256) {
        return _executorStorage().nonces[signer];
    }

    /// @notice Returns the EIP-712 domain separator bound to this proxy and chain.
    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this),
                DOMAIN_SALT
            )
        );
    }

    /// @notice Exposes the active EIP-712 domain according to ERC-5267.
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory domainVersion,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (
            hex"1f",
            "MoistExecutor",
            "1",
            block.chainid,
            address(this),
            DOMAIN_SALT,
            new uint256[](0)
        );
    }

    /// @notice Computes the EIP-712 digest for an execution authorization.
    /// @dev The signer, proxy address, chain, calldata hash, nonce, and deadline are all bound.
    function hashExecute(
        address signer,
        address target,
        uint256 value,
        bytes32 dataHash,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(EXECUTE_TYPEHASH, signer, target, value, dataHash, nonce, deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    /// @notice Returns the implementation API version.
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @notice Grants or revokes an operator's full execution authority.
    function setOperator(address operator, bool authorized) external onlyOwner {
        if (operator == address(0)) revert InvalidAddress();
        _executorStorage().operators[operator] = authorized;
        emit OperatorUpdated(operator, authorized);
    }

    /// @notice Sets the contract used to resolve calldata selectors into destinations.
    function setResolver(address newResolver) external onlyOwner {
        if (newResolver == address(0) || newResolver.code.length == 0) revert InvalidAddress();
        ExecutorStorage storage state = _executorStorage();
        address previous = state.resolver;
        state.resolver = newResolver;
        emit ResolverUpdated(previous, newResolver);
    }

    /// @notice Nominates a new owner, who must call `acceptOwnership`.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        ExecutorStorage storage state = _executorStorage();
        state.pendingOwner = newOwner;
        emit OwnershipTransferStarted(state.owner, newOwner);
    }

    /// @notice Accepts ownership from the currently configured pending owner.
    function acceptOwnership() external {
        ExecutorStorage storage state = _executorStorage();
        if (msg.sender != state.pendingOwner) revert Unauthorized(msg.sender);
        address previousOwner = state.owner;
        state.owner = msg.sender;
        state.pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    /// @notice Executes one arbitrary call as the owner or an approved operator.
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyAuthorized
        nonReentrant
        returns (bytes memory result)
    {
        result = _call(0, target, value, data);
    }

    /// @notice Executes an atomic sequence of arbitrary calls.
    function executeBatch(Call[] calldata calls)
        external
        onlyAuthorized
        nonReentrant
        returns (bytes[] memory results)
    {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            Call calldata item = calls[i];
            results[i] = _call(i, item.target, item.value, item.data);
        }
    }

    /// @notice Resolves the calldata selector and executes the resulting destination call.
    function executeResolved(uint256 value, bytes calldata data)
        external
        onlyAuthorized
        nonReentrant
        returns (bytes memory result)
    {
        if (data.length < 4) revert InvalidAddress();
        address configuredResolver = _executorStorage().resolver;
        if (configuredResolver == address(0)) revert InvalidAddress();
        address target = IMoistResolver(configuredResolver).resolve(bytes4(data[:4]));
        result = _call(0, target, value, data);
    }

    /// @notice Relays an owner/operator-authorized EIP-712 call.
    /// @dev Supports EOA signatures and ERC-1271 contract-wallet signatures.
    function executeSigned(
        address signer,
        Call calldata request,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external onlyAuthorized nonReentrant returns (bytes memory result) {
        if (block.timestamp > deadline) revert SignatureExpired(deadline);

        bytes32 digest = hashExecute(
            signer,
            request.target,
            request.value,
            keccak256(request.data),
            nonce,
            deadline
        );
        ExecutorStorage storage state = _executorStorage();
        if (signer != state.owner && !state.operators[signer]) revert Unauthorized(signer);
        if (!SignatureChecker.isValidSignatureNowCalldata(signer, digest, signature)) {
            revert InvalidSignature(signer);
        }

        uint256 expectedNonce = state.nonces[signer];
        if (nonce != expectedNonce) revert InvalidNonce(signer, expectedNonce, nonce);
        state.nonces[signer] = expectedNonce + 1;

        result = _call(0, request.target, request.value, request.data);
        emit SignedCallExecuted(signer, msg.sender, nonce);
    }

    /// @notice Transfers native currency from the proxy to `recipient`.
    function withdrawNative(address payable recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        _call(0, recipient, amount, "");
    }

    /// @notice Safely transfers ERC-20 tokens from the proxy to `recipient`.
    function withdrawToken(address token, address recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (token == address(0) || recipient == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }

    /// @notice Accepts native currency and records its sender and amount.
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /// @dev Executes a low-level call and converts failure data into a consistent indexed error.
    function _call(uint256 index, address target, uint256 value, bytes memory data)
        private
        returns (bytes memory result)
    {
        if (target == address(0)) revert InvalidAddress();
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert CallFailed(index, target, result);
        emit CallExecuted(index, target, value, result);
    }

    /// @dev Returns the ERC-7201 executor storage namespace.
    function _executorStorage() private pure returns (ExecutorStorage storage state) {
        bytes32 slot = EXECUTOR_STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }
}
