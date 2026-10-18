// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal interface for Gains Network delegated trading.
interface IGainsTradingDelegation {
    function delegatedTradingAction(address trader, bytes calldata callData)
        external returns (bytes memory);
    function getTradingDelegate(address trader) external view returns (address);
}

/// @title MoistTrader
/// @notice Dedicated Gains trading delegate for a single trader on Base.
/// @dev DCC3 must call Gains.setTradingDelegate(address(this)) from the trader wallet.
///      Do not deposit collateral here: trades are attributed to the trader by Gains.
contract MoistTrader {
    error Unauthorized();
    error ZeroAddress();
    error InvalidTarget();
    error SelectorNotAllowed(bytes4 selector);
    error NotDelegated();
    error Reentrant();
    error EmptyCall();

    address public immutable trader;
    address public immutable gains;
    address public owner;
    address public pendingOwner;
    mapping(address => bool) public operators;
    mapping(bytes4 => bool) public allowedSelectors;
    uint256 private _entered = 1;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OperatorUpdated(address indexed operator, bool authorized);
    event SelectorUpdated(bytes4 indexed selector, bool allowed);
    event TradeExecuted(address indexed caller, address indexed trader, bytes4 indexed selector, bytes result);

    constructor(address trader_, address gains_, address owner_) {
        if (trader_ == address(0) || gains_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        if (gains_.code.length == 0) revert InvalidTarget();
        trader = trader_;
        gains = gains_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && !operators[msg.sender]) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_entered != 1) revert Reentrant();
        _entered = 2;
        _;
        _entered = 1;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert ZeroAddress();
        pendingOwner = nextOwner;
        emit OwnershipTransferStarted(owner, nextOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert Unauthorized();
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function setOperator(address operator, bool authorized) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        operators[operator] = authorized;
        emit OperatorUpdated(operator, authorized);
    }

    /// @notice Explicit allowlist of Gains trading function selectors; all disabled initially.
    function setAllowedSelector(bytes4 selector, bool allowed) external onlyOwner {
        allowedSelectors[selector] = allowed;
        emit SelectorUpdated(selector, allowed);
    }

    /// @notice Read-only confirmation that Gains recognizes this contract as trader's delegate.
    function isDelegated() public view returns (bool) {
        return IGainsTradingDelegation(gains).getTradingDelegate(trader) == address(this);
    }

    /// @notice Execute an allowlisted Gains trading action on behalf of trader.
    /// @param callData ABI-encoded Gains trading function call, not delegatedTradingAction itself.
    function trade(bytes calldata callData)
        external onlyAuthorized nonReentrant returns (bytes memory result)
    {
        if (callData.length < 4) revert EmptyCall();
        bytes4 selector = bytes4(callData[:4]);
        if (!allowedSelectors[selector]) revert SelectorNotAllowed(selector);
        if (!isDelegated()) revert NotDelegated();
        result = IGainsTradingDelegation(gains).delegatedTradingAction(trader, callData);
        emit TradeExecuted(msg.sender, trader, selector, result);
    }
}
