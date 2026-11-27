// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Upgradeable selector-to-destination registry for MoistExecutor.
contract MoistResolver {
    struct Route {
        address destination;
        bool enabled;
    }

    /// @custom:storage-location erc7201:moistly.storage.MoistResolver
    struct ResolverStorage {
        address owner;
        address pendingOwner;
        address fallbackDestination;
        bool initialized;
        mapping(bytes4 => Route) routes;
    }

    bytes32 private constant RESOLVER_STORAGE_SLOT =
        0xa8128ea34b5beeb345ac9745365058a31770f4efb4385a34b70c366ebabff900;

    error AlreadyInitialized();
    error InvalidAddress();
    error InvalidCalldata();
    error RouteNotFound(bytes4 selector);
    error Unauthorized(address caller);

    event Initialized(address indexed owner);
    event RouteUpdated(bytes4 indexed selector, address indexed destination, bool enabled);
    event FallbackUpdated(address indexed previousDestination, address indexed newDestination);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _resolverStorage().initialized = true;
    }

    modifier onlyOwner() {
        if (msg.sender != _resolverStorage().owner) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Initializes proxy storage and assigns its first owner.
    /// @dev Must be supplied atomically to the proxy constructor in production.
    function initialize(address initialOwner) external {
        ResolverStorage storage state = _resolverStorage();
        if (state.initialized) revert AlreadyInitialized();
        if (initialOwner == address(0)) revert InvalidAddress();
        state.initialized = true;
        state.owner = initialOwner;
        emit Initialized(initialOwner);
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Returns the address authorized to administer routes.
    function owner() external view returns (address) {
        return _resolverStorage().owner;
    }

    /// @notice Returns the address nominated to accept ownership.
    function pendingOwner() external view returns (address) {
        return _resolverStorage().pendingOwner;
    }

    /// @notice Returns the fallback destination used when no selector route is enabled.
    function fallbackDestination() external view returns (address) {
        return _resolverStorage().fallbackDestination;
    }

    /// @notice Returns the configured destination and enabled state for a selector.
    function route(bytes4 selector) external view returns (address destination, bool enabled) {
        Route storage configured = _resolverStorage().routes[selector];
        return (configured.destination, configured.enabled);
    }

    /// @notice Resolves a selector to its enabled route or the configured fallback.
    function resolve(bytes4 selector) public view returns (address destination) {
        ResolverStorage storage state = _resolverStorage();
        Route storage configured = state.routes[selector];
        if (configured.enabled) return configured.destination;
        destination = state.fallbackDestination;
        if (destination == address(0)) revert RouteNotFound(selector);
    }

    /// @notice Extracts and resolves the first four bytes of calldata.
    function resolveCalldata(bytes calldata data) external view returns (address destination) {
        if (data.length < 4) revert InvalidCalldata();
        bytes4 selector = bytes4(data[:4]);
        return resolve(selector);
    }

    /// @notice Creates, updates, disables, or removes a selector route.
    /// @dev Enabled destinations must contain deployed contract code.
    function setRoute(bytes4 selector, address destination, bool enabled) external onlyOwner {
        if (enabled && (destination == address(0) || destination.code.length == 0)) {
            revert InvalidAddress();
        }
        _resolverStorage().routes[selector] = Route(destination, enabled);
        emit RouteUpdated(selector, destination, enabled);
    }

    /// @notice Sets the fallback destination; use the zero address to disable fallback routing.
    function setFallback(address destination) external onlyOwner {
        if (destination != address(0) && destination.code.length == 0) revert InvalidAddress();
        ResolverStorage storage state = _resolverStorage();
        address previous = state.fallbackDestination;
        state.fallbackDestination = destination;
        emit FallbackUpdated(previous, destination);
    }

    /// @notice Nominates a new owner, who must call `acceptOwnership`.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        ResolverStorage storage state = _resolverStorage();
        state.pendingOwner = newOwner;
        emit OwnershipTransferStarted(state.owner, newOwner);
    }

    /// @notice Accepts ownership from the currently configured pending owner.
    function acceptOwnership() external {
        ResolverStorage storage state = _resolverStorage();
        if (msg.sender != state.pendingOwner) revert Unauthorized(msg.sender);
        address previous = state.owner;
        state.owner = msg.sender;
        state.pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    /// @notice Returns the resolver implementation API version.
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @dev Returns the ERC-7201 resolver storage namespace.
    function _resolverStorage() private pure returns (ResolverStorage storage state) {
        bytes32 slot = RESOLVER_STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }
}
