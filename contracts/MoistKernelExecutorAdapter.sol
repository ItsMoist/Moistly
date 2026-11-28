// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice ERC-7579 executor-module adapter for Kernel v3.1 (kernel.advanced.v0.3.1), implementation
///         0xbac849bb641841b44e965fb01a4bf5f074f84b4d.
/// @dev Install on each Kernel account with installModule(2, adapter, initData) where Kernel v3.1 expects
///          initData = abi.encodePacked(hook, abi.encode(executorData, hookData))
///      hook = address(0) installs without a hook (hookData = ""). executorData is passed to onInstall and is
///      either abi.encode(moistExecutorProxy) (any target) or
///      abi.encode(moistExecutorProxy, address[] allowedTargets) (only the listed targets).
///      Then call MoistExecutor.execute(adapter, 0, abi.encodeCall(
///      MoistKernelExecutorAdapter.executeSingle, (kernelAccount, target, value, callData))).
///      The MoistExecutor proxy is the caller policy boundary; this adapter additionally forbids calls
///      into the account itself (which would let the executor rewrite validators/modules) and enforces
///      the account's optional target allowlist. This adapter intentionally holds no user assets.
interface IKernelV3ExecutorAccount {
    /// @dev Kernel v3 declares this argument as its user-defined ExecMode type.
    ///      ExecMode is ABI-compatible with bytes32.
    function executeFromExecutor(bytes32 execMode, bytes calldata executionCalldata)
        external
        payable
        returns (bytes[] memory returnData);
}

interface IERC7579Module {
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
    function onInstall(bytes calldata data) external;
    function onUninstall(bytes calldata data) external;
}

contract MoistKernelExecutorAdapter is IERC7579Module {
    uint256 private constant MODULE_TYPE_EXECUTOR = 2;

    // ERC-7579 ModeCode layout: [callType:1][execType:1][unused:4]
    // [modeSelector:4][modePayload:22]. execType 0x00 means revert on failure.
    // The remaining selector/payload bytes are zero for the standard modes used here.
    bytes32 private constant MODE_SINGLE_DEFAULT = bytes32(0);
    bytes32 private constant MODE_BATCH_DEFAULT = bytes32(uint256(1) << 248);

    struct Execution {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @dev Per-account allowlist. The trusted address must be the MoistExecutor proxy,
    ///      not its implementation contract, because Kernel sees msg.sender as the proxy.
    mapping(address account => address executor) public trustedExecutor;

    /// @dev When true for an account, only targets allowlisted for its current install are callable.
    mapping(address account => bool) public targetRestricted;

    /// @dev Bumped on every install so allowlists from a previous install are discarded.
    mapping(address account => uint256) public installGeneration;

    mapping(address account => mapping(uint256 generation => mapping(address target => bool))) private _allowedTarget;

    error InvalidAccount();
    error InvalidExecutor();
    error AlreadyInstalled();
    error NotInstalled();
    error UnauthorizedCaller(address caller);
    error InvalidTarget();
    error EmptyBatch();
    error SelfCallForbidden();
    error ModuleLifecycleCallForbidden(address target);
    error TargetNotAllowed(address target);

    event AdapterInstalled(address indexed account, address indexed trustedExecutor);
    event AdapterUninstalled(address indexed account);
    event AccountExecution(address indexed account, address indexed caller, uint256 calls);
    event TargetAllowed(address indexed account, address indexed target, bool allowed);
    event TargetRestrictionSet(address indexed account, bool restricted);

    modifier onlyTrustedExecutor(address account) {
        address expected = trustedExecutor[account];
        if (expected == address(0)) revert NotInstalled();
        if (msg.sender != expected) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /// @inheritdoc IERC7579Module
    /// @dev Called by the Kernel account during installModule(2, adapter, initData) with the
    ///      executorData portion: abi.encode(executor) or abi.encode(executor, address[] allowedTargets).
    function onInstall(bytes calldata data) external {
        if (msg.sender.code.length == 0) revert InvalidAccount();
        if (trustedExecutor[msg.sender] != address(0)) revert AlreadyInstalled();

        address executor;
        address[] memory targets;
        if (data.length == 32) {
            executor = abi.decode(data, (address));
        } else {
            (executor, targets) = abi.decode(data, (address, address[]));
        }
        if (executor == address(0) || executor.code.length == 0) revert InvalidExecutor();

        uint256 generation = ++installGeneration[msg.sender];
        trustedExecutor[msg.sender] = executor;
        emit AdapterInstalled(msg.sender, executor);

        if (targets.length != 0) {
            targetRestricted[msg.sender] = true;
            emit TargetRestrictionSet(msg.sender, true);
            for (uint256 i; i < targets.length; ++i) {
                _allowedTarget[msg.sender][generation][targets[i]] = true;
                emit TargetAllowed(msg.sender, targets[i], true);
            }
        }
    }

    /// @inheritdoc IERC7579Module
    /// @dev Called by the Kernel account during uninstallModule(2, adapter, deInitData).
    function onUninstall(bytes calldata) external {
        if (trustedExecutor[msg.sender] == address(0)) revert NotInstalled();
        delete trustedExecutor[msg.sender];
        delete targetRestricted[msg.sender];
        emit AdapterUninstalled(msg.sender);
    }

    /// @notice Lets an account with this adapter installed turn its target allowlist on or off.
    function setTargetRestricted(bool restricted) external {
        if (trustedExecutor[msg.sender] == address(0)) revert NotInstalled();
        targetRestricted[msg.sender] = restricted;
        emit TargetRestrictionSet(msg.sender, restricted);
    }

    /// @notice Lets an account with this adapter installed edit its target allowlist.
    function setTargetAllowed(address target, bool allowed) external {
        if (trustedExecutor[msg.sender] == address(0)) revert NotInstalled();
        _allowedTarget[msg.sender][installGeneration[msg.sender]][target] = allowed;
        emit TargetAllowed(msg.sender, target, allowed);
    }

    /// @notice Whether `target` is allowlisted for `account`'s current install.
    function isTargetAllowed(address account, address target) public view returns (bool) {
        return trustedExecutor[account] != address(0) && _allowedTarget[account][installGeneration[account]][target];
    }

    /// @notice Execute one call from a Kernel account via its installed executor module.
    /// @dev The trusted MoistExecutor proxy is the only caller allowed to select accounts
    ///      and targets. Kernel independently checks that this adapter is installed.
    function executeSingle(address account, address target, uint256 value, bytes calldata callData)
        external
        onlyTrustedExecutor(account)
        returns (bytes[] memory results)
    {
        if (account.code.length == 0) revert InvalidAccount();
        _checkTarget(account, target, callData);

        // ERC-7579 single-call encoding is packed: target || value || callData.
        bytes memory executionCalldata = abi.encodePacked(target, value, callData);
        results = IKernelV3ExecutorAccount(account).executeFromExecutor(MODE_SINGLE_DEFAULT, executionCalldata);

        emit AccountExecution(account, msg.sender, 1);
    }

    /// @notice Execute an atomic batch of calls from a Kernel account.
    /// @dev ERC-7579 batch data is abi.encode(Execution[]), with fields in
    ///      (address target, uint256 value, bytes callData) order.
    function executeBatch(address account, Execution[] calldata calls)
        external
        onlyTrustedExecutor(account)
        returns (bytes[] memory results)
    {
        if (account.code.length == 0) revert InvalidAccount();
        if (calls.length == 0) revert EmptyBatch();

        Execution[] memory executions = new Execution[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            _checkTarget(account, calls[i].target, calls[i].callData);
            executions[i] = Execution({target: calls[i].target, value: calls[i].value, callData: calls[i].callData});
        }

        results = IKernelV3ExecutorAccount(account).executeFromExecutor(MODE_BATCH_DEFAULT, abi.encode(executions));

        emit AccountExecution(account, msg.sender, calls.length);
    }

    /// @dev Blocks calls that could hand control of the account to someone else: calls into the account
    ///      itself (passes Kernel's onlyEntryPointOrSelfOrRoot) and ERC-7579 onInstall/onUninstall on any
    ///      module, which modules key by msg.sender (e.g. ECDSAValidator.onInstall would replace the owner).
    function _checkTarget(address account, address target, bytes calldata callData) private view {
        if (target == address(0)) revert InvalidTarget();
        if (target == account) revert SelfCallForbidden();
        if (callData.length >= 4) {
            bytes4 selector = bytes4(callData[:4]);
            if (selector == IERC7579Module.onInstall.selector || selector == IERC7579Module.onUninstall.selector) {
                revert ModuleLifecycleCallForbidden(target);
            }
        }
        if (targetRestricted[account] && !isTargetAllowed(account, target)) {
            revert TargetNotAllowed(target);
        }
    }
}
