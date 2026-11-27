// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISafeModuleExecutor {
    enum Operation {
        Call,
        DelegateCall
    }

    function execTransactionFromModule(address to, uint256 value, bytes calldata data, Operation operation)
        external
        returns (bool success);
}

interface IERC20Transfer {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Narrow Safe module that can only sweep ETH and ERC20s from one Safe to one fixed recipient.
contract MoistSafeSweepModule {
    address public immutable safe;
    address payable public immutable recipient;

    error InvalidAddress();
    error SweepFailed();
    error TokenBalanceQueryFailed(address token);

    event EtherSwept(address indexed safe, address indexed recipient, uint256 amount);
    event TokenSwept(address indexed safe, address indexed token, address indexed recipient, uint256 amount);

    constructor(address safe_, address payable recipient_) {
        if (safe_ == address(0) || recipient_ == address(0)) {
            revert InvalidAddress();
        }

        safe = safe_;
        recipient = recipient_;
    }

    function sweepEther(uint256 amount) public {
        bool success = ISafeModuleExecutor(safe).execTransactionFromModule(
            recipient,
            amount,
            "",
            ISafeModuleExecutor.Operation.Call
        );
        if (!success) {
            revert SweepFailed();
        }

        emit EtherSwept(safe, recipient, amount);
    }

    function sweepAllEther() external returns (uint256 amount) {
        amount = safe.balance;
        sweepEther(amount);
    }

    function sweepToken(address token, uint256 amount) public {
        if (token == address(0)) {
            revert InvalidAddress();
        }

        bool success = ISafeModuleExecutor(safe).execTransactionFromModule(
            token,
            0,
            abi.encodeWithSelector(IERC20Transfer.transfer.selector, recipient, amount),
            ISafeModuleExecutor.Operation.Call
        );
        if (!success) {
            revert SweepFailed();
        }

        emit TokenSwept(safe, token, recipient, amount);
    }

    function sweepAllToken(address token) external returns (uint256 amount) {
        if (token == address(0)) {
            revert InvalidAddress();
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Transfer.balanceOf.selector, safe));
        if (!ok || data.length < 32) {
            revert TokenBalanceQueryFailed(token);
        }

        amount = abi.decode(data, (uint256));
        sweepToken(token, amount);
    }
}
