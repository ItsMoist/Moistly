// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMoistBeaconRouterResolver {
    function resolve(bytes4 selector) external view returns (address destination);
}

interface IMoistBeaconRouterExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function executeSigned(
        address signer,
        Call calldata request,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bytes memory result);

    function hashExecute(
        address signer,
        address target,
        uint256 value,
        bytes32 dataHash,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32);
}

/// @notice User-facing resolver and EIP-712 relay facade.
/// @dev Holds no independent execution authority or asset custody.
contract MoistBeaconRouter {
    /// @custom:storage-location erc7201:moistly.storage.MoistBeaconRouter
    struct RouterStorage {
        address owner;
        address pendingOwner;
        address executor;
        address resolver;
        bool initialized;
        mapping(address => bool) relayers;
    }

    bytes32 private constant ROUTER_STORAGE_SLOT =
        0x254d794e4da88a10672a19d59b9373b41736054f91b6000c3b50bdb4dbb71e00;

    error AlreadyInitialized();
    error InvalidAddress();
    error InvalidCalldata();
    error Unauthorized(address caller);

    event Initialized(address indexed owner, address indexed executor, address indexed resolver);
    event ExecutorUpdated(address indexed previousExecutor, address indexed newExecutor);
    event ResolverUpdated(address indexed previousResolver, address indexed newResolver);
    event Routed(
        address indexed relayer,
        address indexed destination,
        bytes4 indexed selector,
        uint256 nonce
    );
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RelayerUpdated(address indexed relayer, bool authorized);

    constructor() {
        _routerStorage().initialized = true;
    }

    modifier onlyOwner() {
        if (msg.sender != _routerStorage().owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyAuthorized() {
        RouterStorage storage state = _routerStorage();
        if (msg.sender != state.owner && !state.relayers[msg.sender]) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /// @notice Initializes proxy storage with its owner, executor, and resolver.
    /// @dev Must be supplied atomically to the proxy constructor in production.
    function initialize(address initialOwner, address executor_, address resolver_) external {
        RouterStorage storage state = _routerStorage();
        if (state.initialized) revert AlreadyInitialized();
        _requireContract(executor_);
        _requireContract(resolver_);
        if (initialOwner == address(0)) revert InvalidAddress();

        state.initialized = true;
        state.owner = initialOwner;
        state.executor = executor_;
        state.resolver = resolver_;
        emit Initialized(initialOwner, executor_, resolver_);
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Returns the address authorized to administer the router.
    function owner() external view returns (address) {
        return _routerStorage().owner;
    }

    /// @notice Returns the executor that verifies signatures and performs calls.
    function executor() external view returns (address) {
        return _routerStorage().executor;
    }

    /// @notice Returns the resolver used to convert selectors into destinations.
    function resolver() external view returns (address) {
        return _routerStorage().resolver;
    }

    /// @notice Reports whether an address may submit signed calls through this router.
    function isRelayer(address account) external view returns (bool) {
        return _routerStorage().relayers[account];
    }

    /// @notice Resolves a call and returns the exact EIP-712 digest that must be signed.
    function preview(
        address signer,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 deadline
    ) external view returns (address destination, bytes32 digest) {
        bytes4 selector = _selector(data);
        RouterStorage storage state = _routerStorage();
        destination = IMoistBeaconRouterResolver(state.resolver).resolve(selector);
        digest = IMoistBeaconRouterExecutor(state.executor).hashExecute(
            signer, destination, value, keccak256(data), nonce, deadline
        );
    }

    /// @notice Resolves and relays a signed call through the configured executor.
    /// @dev The caller must be the router owner or an approved relayer.
    function routeSigned(
        address signer,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external onlyAuthorized returns (bytes memory result) {
        bytes4 selector = _selector(data);
        RouterStorage storage state = _routerStorage();
        address destination = IMoistBeaconRouterResolver(state.resolver).resolve(selector);
        IMoistBeaconRouterExecutor.Call memory request =
            IMoistBeaconRouterExecutor.Call(destination, value, data);
        result = IMoistBeaconRouterExecutor(state.executor).executeSigned(
            signer, request, nonce, deadline, signature
        );
        emit Routed(msg.sender, destination, selector, nonce);
    }

    /// @notice Grants or revokes permission to submit signed calls through the router.
    function setRelayer(address relayer, bool authorized) external onlyOwner {
        if (relayer == address(0)) revert InvalidAddress();
        _routerStorage().relayers[relayer] = authorized;
        emit RelayerUpdated(relayer, authorized);
    }

    /// @notice Changes the executor after verifying that it contains contract code.
    function setExecutor(address newExecutor) external onlyOwner {
        _requireContract(newExecutor);
        RouterStorage storage state = _routerStorage();
        address previous = state.executor;
        state.executor = newExecutor;
        emit ExecutorUpdated(previous, newExecutor);
    }

    /// @notice Changes the resolver after verifying that it contains contract code.
    function setResolver(address newResolver) external onlyOwner {
        _requireContract(newResolver);
        RouterStorage storage state = _routerStorage();
        address previous = state.resolver;
        state.resolver = newResolver;
        emit ResolverUpdated(previous, newResolver);
    }

    /// @notice Nominates a new owner, who must call `acceptOwnership`.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        RouterStorage storage state = _routerStorage();
        state.pendingOwner = newOwner;
        emit OwnershipTransferStarted(state.owner, newOwner);
    }

    /// @notice Accepts ownership from the currently configured pending owner.
    function acceptOwnership() external {
        require(msg.sender != address(0));
        RouterStorage storage state = _routerStorage();
        if (msg.sender != state.pendingOwner) revert Unauthorized(msg.sender);
        address previous = state.owner;
        state.owner = msg.sender;
        state.pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    /// @notice Returns the router implementation API version.
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @dev Extracts a selector and rejects calldata shorter than four bytes.
    function _selector(bytes calldata data) private pure returns (bytes4 selector) {
        if (data.length < 4) revert InvalidCalldata();
        selector = bytes4(data[:4]);
    }

    /// @dev Rejects the zero address and addresses without deployed code.
    function _requireContract(address account) private view {
        if (account == address(0) || account.code.length == 0) revert InvalidAddress();
    }

    /// @dev Returns the ERC-7201 router storage namespace.
    function _routerStorage() private pure returns (RouterStorage storage state) {
        bytes32 slot = ROUTER_STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }
}
