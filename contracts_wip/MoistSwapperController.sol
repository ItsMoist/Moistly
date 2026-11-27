// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMoistManagedSwapper {
    struct QuotePair {
        address base;
        address quote;
    }

    struct SetPairScaledOfferFactorParams {
        QuotePair quotePair;
        uint32 scaledOfferFactor;
    }

    function setBeneficiary(address beneficiary) external;
    function setTokenToBeneficiary(address tokenToBeneficiary) external;
    function setOracle(address oracle) external;
    function setDefaultScaledOfferFactor(uint32 defaultScaledOfferFactor) external;
    function setPairScaledOfferFactors(SetPairScaledOfferFactorParams[] calldata params) external;
    function setPaused(bool paused) external;
    function transferOwnership(address newOwner) external;
}

/// @notice Beacon-upgradeable control boundary for one existing Swapper deployment.
/// @dev The managed Swapper must transfer ownership to this proxy after deployment and review.
contract MoistSwapperController {
    /// @custom:storage-location erc7201:moistly.storage.MoistSwapperController
    struct ControllerStorage {
        address owner;
        address pendingOwner;
        address executor;
        address managedSwapper;
        bool initialized;
        uint256 entered;
    }

    bytes32 private constant CONTROLLER_STORAGE_SLOT =
        0xfe101abef9f88c86ec0057c39719205d5929187fb7d94bf7e573a8d0dcbb9300;

    error AlreadyInitialized();
    error InvalidAddress();
    error Unauthorized(address caller);
    error ReentrantCall();

    event Initialized(
        address indexed owner,
        address indexed executor,
        address indexed managedSwapper
    );
    event ExecutorUpdated(address indexed previousExecutor, address indexed newExecutor);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MoistSwapperActionExecuted(bytes4 indexed selector);
    event ManagedSwapperOwnershipTransferred(address indexed newOwner);

    constructor() {
        _controllerStorage().initialized = true;
    }

    modifier onlyOwner() {
        if (msg.sender != _controllerStorage().owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyControlPlane() {
        ControllerStorage storage state = _controllerStorage();
        if (msg.sender != state.owner && msg.sender != state.executor) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier nonReentrant() {
        ControllerStorage storage state = _controllerStorage();
        if (state.entered == 2) revert ReentrantCall();
        state.entered = 2;
        _;
        state.entered = 1;
    }

    /// @notice Initializes proxy storage with DCC3 control, the existing Executor, and a Swapper.
    /// @dev Must be called atomically by the proxy constructor.
    function initialize(address initialOwner, address executor_, address managedSwapper_) external {
        ControllerStorage storage state = _controllerStorage();
        if (state.initialized) revert AlreadyInitialized();
        _requireContract(executor_);
        _requireContract(managedSwapper_);
        if (initialOwner == address(0)) revert InvalidAddress();

        state.initialized = true;
        state.entered = 1;
        state.owner = initialOwner;
        state.executor = executor_;
        state.managedSwapper = managedSwapper_;
        emit Initialized(initialOwner, executor_, managedSwapper_);
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Returns the address with controller administration authority.
    function owner() external view returns (address) {
        return _controllerStorage().owner;
    }

    /// @notice Returns the address nominated to accept controller ownership.
    function pendingOwner() external view returns (address) {
        return _controllerStorage().pendingOwner;
    }

    /// @notice Returns the only MoistExecutor authorized to submit routed Swapper actions.
    function executor() external view returns (address) {
        return _controllerStorage().executor;
    }

    /// @notice Returns the immutable-by-policy Swapper managed by this proxy.
    function managedSwapper() external view returns (address) {
        return _controllerStorage().managedSwapper;
    }

    /// @notice Returns the implementation API version.
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /// @notice Changes the authorized MoistExecutor after validating deployed code.
    function setExecutor(address newExecutor) external onlyOwner {
        _requireContract(newExecutor);
        ControllerStorage storage state = _controllerStorage();
        address previous = state.executor;
        state.executor = newExecutor;
        emit ExecutorUpdated(previous, newExecutor);
    }

    /// @notice Nominates a new controller owner, who must explicitly accept ownership.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        ControllerStorage storage state = _controllerStorage();
        state.pendingOwner = newOwner;
        emit OwnershipTransferStarted(state.owner, newOwner);
    }

    /// @notice Accepts controller ownership from the current pending owner.
    function acceptOwnership() external {
        ControllerStorage storage state = _controllerStorage();
        if (msg.sender != state.pendingOwner) revert Unauthorized(msg.sender);
        address previous = state.owner;
        state.owner = msg.sender;
        state.pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    /// @notice Routes a reviewed beneficiary update to the managed Swapper.
    function setMoistSwapperBeneficiary(address beneficiary)
        external
        onlyControlPlane
        nonReentrant
    {
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setBeneficiary(beneficiary);
        emit MoistSwapperActionExecuted(this.setMoistSwapperBeneficiary.selector);
    }

    /// @notice Routes a reviewed beneficiary-token update to the managed Swapper.
    function setMoistSwapperTokenToBeneficiary(address tokenToBeneficiary)
        external
        onlyControlPlane
        nonReentrant
    {
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setTokenToBeneficiary(
            tokenToBeneficiary
        );
        emit MoistSwapperActionExecuted(this.setMoistSwapperTokenToBeneficiary.selector);
    }

    /// @notice Routes a reviewed oracle update to the managed Swapper.
    function setMoistSwapperOracle(address oracle) external onlyControlPlane nonReentrant {
        if (oracle == address(0)) revert InvalidAddress();
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setOracle(oracle);
        emit MoistSwapperActionExecuted(this.setMoistSwapperOracle.selector);
    }

    /// @notice Routes a reviewed default offer-factor update to the managed Swapper.
    function setMoistSwapperDefaultScaledOfferFactor(uint32 scaledOfferFactor)
        external
        onlyControlPlane
        nonReentrant
    {
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setDefaultScaledOfferFactor(
            scaledOfferFactor
        );
        emit MoistSwapperActionExecuted(this.setMoistSwapperDefaultScaledOfferFactor.selector);
    }

    /// @notice Routes reviewed pair-specific offer-factor updates to the managed Swapper.
    function setMoistSwapperPairScaledOfferFactors(
        IMoistManagedSwapper.SetPairScaledOfferFactorParams[] calldata params
    ) external onlyControlPlane nonReentrant {
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setPairScaledOfferFactors(params);
        emit MoistSwapperActionExecuted(this.setMoistSwapperPairScaledOfferFactors.selector);
    }

    /// @notice Routes a reviewed pause-state update to the managed Swapper.
    function setMoistSwapperPaused(bool paused) external onlyControlPlane nonReentrant {
        IMoistManagedSwapper(_controllerStorage().managedSwapper).setPaused(paused);
        emit MoistSwapperActionExecuted(this.setMoistSwapperPaused.selector);
    }

    /// @notice Transfers the managed Swapper out of this controller as an emergency migration.
    /// @dev This selector must never be added to MoistResolver; call it directly from the owner.
    function transferManagedSwapperOwnership(address newOwner)
        external
        onlyOwner
        nonReentrant
    {
        if (newOwner == address(0)) revert InvalidAddress();
        IMoistManagedSwapper(_controllerStorage().managedSwapper).transferOwnership(newOwner);
        emit ManagedSwapperOwnershipTransferred(newOwner);
    }

    /// @dev Rejects zero addresses and accounts without deployed contract code.
    function _requireContract(address account) private view {
        if (account == address(0) || account.code.length == 0) revert InvalidAddress();
    }

    /// @dev Returns the ERC-7201 controller storage namespace.
    function _controllerStorage() private pure returns (ControllerStorage storage state) {
        bytes32 slot = CONTROLLER_STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }
}
