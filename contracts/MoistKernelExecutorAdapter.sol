// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice ERC-7579 executor-module adapter for the Kernel implementation at
///         0xbac849bb641841b44e965fb01a4bf5f074f84b4d.
/// @dev Install this module on each Kernel account with initData = abi.encode(moistExecutorProxy).
///      Then call MoistExecutor.execute(adapter, 0, abi.encodeCall(
///      MoistKernelExecutorAdapter.executeSingle, (kernelAccount, target, value, callData))).
///      The MoistExecutor proxy remains the policy boundary: its owner/operator/signature checks
///      run before it calls this adapter. This adapter intentionally holds no user assets.
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

    error InvalidAccount();
    error InvalidExecutor();
    error AlreadyInstalled();
    error NotInstalled();
    error UnauthorizedCaller(address caller);
    error InvalidTarget();
    error EmptyBatch();

    event AdapterInstalled(address indexed account, address indexed trustedExecutor);
    event AdapterUninstalled(address indexed account);
    event AccountExecution(address indexed account, address indexed caller, uint256 calls);

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
    /// @dev Called by the Kernel account during installModule(2, adapter, initData).
    ///      initData must be abi.encode(the MoistExecutor proxy address).
    function onInstall(bytes calldata data) external {
        if (msg.sender.code.length == 0) revert InvalidAccount();
        if (trustedExecutor[msg.sender] != address(0)) revert AlreadyInstalled();

        address executor = abi.decode(data, (address));
        if (executor == address(0) || executor.code.length == 0) revert InvalidExecutor();

        trustedExecutor[msg.sender] = executor;
        emit AdapterInstalled(msg.sender, executor);
    }

    /// @inheritdoc IERC7579Module
    /// @dev Called by the Kernel account during uninstallModule(2, adapter, deInitData).
    function onUninstall(bytes calldata) external {
        if (trustedExecutor[msg.sender] == address(0)) revert NotInstalled();
        delete trustedExecutor[msg.sender];
        emit AdapterUninstalled(msg.sender);
    }

    /// @notice Execute one call from a Kernel account via its installed executor module.
    /// @dev The trusted MoistExecutor proxy is the only caller allowed to select accounts
    ///      and targets. Kernel independently checks that this adapter is installed.
    function executeSingle(
        address account,
        address target,
        uint256 value,
        bytes calldata callData
    ) external onlyTrustedExecutor(account) returns (bytes[] memory results) {
        if (account.code.length == 0) revert InvalidAccount();
        if (target == address(0)) revert InvalidTarget();

        // ERC-7579 single-call encoding is packed: target || value || callData.
        bytes memory executionCalldata = abi.encodePacked(target, value, callData);
        results = IKernelV3ExecutorAccount(account).executeFromExecutor(
            MODE_SINGLE_DEFAULT, executionCalldata
        );

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
            if (calls[i].target == address(0)) revert InvalidTarget();
            executions[i] = Execution({
                target: calls[i].target,
                value: calls[i].value,
                callData: calls[i].callData
            });
        }

        results = IKernelV3ExecutorAccount(account).executeFromExecutor(
            MODE_BATCH_DEFAULT, abi.encode(executions)
        );

        emit AccountExecution(account, msg.sender, calls.length);
    }
}
