// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC-7579 executor module for routing authorized Moistly calls
///         through a Kernel smart account.
/// @dev Install this module on each Kernel account with abi.encode(moistExecutorProxy).
///      The MoistExecutor remains responsible for owner/operator/signature policy.
///      This module is intentionally not a standalone wallet and holds no assets.
interface IERC7579KernelAccount {
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        external
        returns (bytes[] memory returnData);
}

interface IERC7579Module {
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
    function onInstall(bytes calldata data) external;
    function onUninstall(bytes calldata data) external;
}

contract MoistKernelExecutorAdapter is IERC7579Module {
    uint256 private constant MODULE_TYPE_EXECUTOR = 2;
    bytes32 private constant MODE_SINGLE = bytes32(0);
    bytes32 private constant MODE_BATCH = bytes32(uint256(1) << 248);

    struct Execution {
        address target;
        uint256 value;
        bytes callData;
    }

    mapping(address account => address executor) public trustedExecutor;

    error InvalidAccount();
    error InvalidExecutor();
    error AlreadyInstalled();
    error NotInstalled();
    error UnauthorizedCaller(address caller);
    error InvalidTarget();

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
    /// @dev ERC-7579 account calls this hook during module installation.
    function onInstall(bytes calldata data) external {
        if (msg.sender.code.length == 0) revert InvalidAccount();
        if (trustedExecutor[msg.sender] != address(0)) revert AlreadyInstalled();

        address executor = abi.decode(data, (address));
        if (executor == address(0) || executor.code.length == 0) revert InvalidExecutor();

        trustedExecutor[msg.sender] = executor;
        emit AdapterInstalled(msg.sender, executor);
    }

    /// @inheritdoc IERC7579Module
    /// @dev The account calls this hook when removing the module.
    function onUninstall(bytes calldata) external {
        if (trustedExecutor[msg.sender] == address(0)) revert NotInstalled();
        delete trustedExecutor[msg.sender];
        emit AdapterUninstalled(msg.sender);
    }

    /// @notice Execute one call from the Kernel account.
    /// @dev The account must have this module installed; Kernel performs that check
    ///      in executeFromExecutor. The caller must be the trusted MoistExecutor proxy.
    function executeSingle(
        address account,
        address target,
        uint256 value,
        bytes calldata callData
    ) external onlyTrustedExecutor(account) returns (bytes[] memory results) {
        if (account.code.length == 0) revert InvalidAccount();
        if (target == address(0)) revert InvalidTarget();

        bytes memory executionCalldata = abi.encodePacked(target, value, callData);
        results = IERC7579KernelAccount(account).executeFromExecutor(
            MODE_SINGLE, executionCalldata
        );
        emit AccountExecution(account, msg.sender, 1);
    }

    /// @notice Execute an atomic batch from the Kernel account.
    /// @dev ERC-7579 batch execution data is abi.encode(Execution[]), not a custom
    ///      concatenation of target/value/data tuples.
    function executeBatch(address account, Execution[] calldata calls)
        external
        onlyTrustedExecutor(account)
        returns (bytes[] memory results)
    {
        if (account.code.length == 0) revert InvalidAccount();
        if (calls.length == 0) revert InvalidTarget();

        Execution[] memory executions = new Execution[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].target == address(0)) revert InvalidTarget();
            executions[i] = Execution({
                target: calls[i].target,
                value: calls[i].value,
                callData: calls[i].callData
            });
        }

        results = IERC7579KernelAccount(account).executeFromExecutor(
            MODE_BATCH, abi.encode(executions)
        );
        emit AccountExecution(account, msg.sender, calls.length);
    }
}
