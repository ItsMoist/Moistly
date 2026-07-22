// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal owner/executor agent with no delegatecall path.
contract MoistAgent {
    address public immutable owner;
    address public immutable executor;

    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event Received(address indexed sender, uint256 value);

    error Unauthorized(address caller);
    error DelegateCallBlocked();
    error CallFailed(bytes result);
    error ZeroAddress();

    constructor(address owner_, address executor_) {
        if (owner_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        owner = owner_;
        executor = executor_;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        onlyAuthorized
        returns (bytes memory result)
    {
        if (target == address(0)) {
            revert ZeroAddress();
        }

        (bool ok, bytes memory returned) = target.call{value: value}(data);
        if (!ok) {
            revert CallFailed(returned);
        }

        emit Executed(target, value, data, returned);
        return returned;
    }

    function delegateExecute(address, bytes calldata) external pure {
        revert DelegateCallBlocked();
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != executor) {
            revert Unauthorized(msg.sender);
        }
        _;
    }
}
