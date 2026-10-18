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
///      ETH held here is NOT credited as Gains collateral; delegated actions are attributed to trader.
contract MoistTrader {
    error Unauthorized();
    error ZeroAddress();
    error InvalidTarget();
    error SelectorNotAllowed(bytes4 selector);
    error NotDelegated();
    error Reentrant();
    error EmptyCall();
    error InsufficientNativeBalance();
    error NativeTransferFailed();

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
    event NativeDeposited(address indexed sender, uint256 amount);
    event NativeWithdrawn(address indexed trader, uint256 amount);

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

    /// @notice Accept ETH for safekeeping. This does not fund a Gains trading position.
    receive() external payable {
        emit NativeDeposited(msg.sender, msg.value);
    }

    function deposit() external payable {
        emit NativeDeposited(msg.sender, msg.value);
    }

    /// @notice Return unused native ETH to the immutable trader address.
    /// @dev Only owner can withdraw; operators cannot withdraw ETH.
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        if (amount > address(this).balance) revert InsufficientNativeBalance();
        (bool ok, ) = payable(trader).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit NativeWithdrawn(trader, amount);
    }

    function nativeBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Increase collateral / exposure on an existing Gains position.
    function increasePositionSize(uint32 index, uint120 collateralDelta, uint24 leverageDelta, uint64 expectedPrice, uint16 maxSlippageP)
        external onlyAuthorized nonReentrant returns (bytes memory)
    {
        return _trade(abi.encodeWithSignature("increasePositionSize(uint32,uint120,uint24,uint64,uint16)", index, collateralDelta, leverageDelta, expectedPrice, maxSlippageP));
    }

    /// @notice Withdraw part of a position's collateral by reducing its size through Gains.
    function decreasePositionSize(uint32 index, uint120 collateralDelta, uint24 leverageDelta, uint64 expectedPrice)
        external onlyAuthorized nonReentrant returns (bytes memory)
    {
        return _trade(abi.encodeWithSignature("decreasePositionSize(uint32,uint120,uint24,uint64)", index, collateralDelta, leverageDelta, expectedPrice));
    }

    /// @notice Close a position, with settlement performed by Gains for the trader.
    function closeTradeMarket(uint32 index, uint64 expectedPrice)
        external onlyAuthorized nonReentrant returns (bytes memory)
    {
        return _trade(abi.encodeWithSignature("closeTradeMarket(uint32,uint64)", index, expectedPrice));
    }

    function updateTp(uint32 index, uint64 newTp) external onlyAuthorized nonReentrant returns (bytes memory) {
        return _trade(abi.encodeWithSignature("updateTp(uint32,uint64)", index, newTp));
    }

    function updateSl(uint32 index, uint64 newSl) external onlyAuthorized nonReentrant returns (bytes memory) {
        return _trade(abi.encodeWithSignature("updateSl(uint32,uint64)", index, newSl));
    }

    function updateLeverage(uint32 index, uint24 newLeverage) external onlyAuthorized nonReentrant returns (bytes memory) {
        return _trade(abi.encodeWithSignature("updateLeverage(uint32,uint24)", index, newLeverage));
    }

    function cancelOpenOrder(uint32 index) external onlyAuthorized nonReentrant returns (bytes memory) {
        return _trade(abi.encodeWithSignature("cancelOpenOrder(uint32)", index));
    }

    /// @notice Execute an allowlisted Gains trading action on behalf of trader.
    /// @param callData ABI-encoded Gains trading function call, not delegatedTradingAction itself.
    function trade(bytes calldata callData)
        external onlyAuthorized nonReentrant returns (bytes memory result)
    {
        return _trade(callData);
    }

    function _trade(bytes memory callData) internal returns (bytes memory result) {
        if (callData.length < 4) revert EmptyCall();
        bytes4 selector;
        assembly { selector := mload(add(callData, 32)) }
        if (!allowedSelectors[selector]) revert SelectorNotAllowed(selector);
        if (!isDelegated()) revert NotDelegated();
        result = IGainsTradingDelegation(gains).delegatedTradingAction(trader, callData);
        emit TradeExecuted(msg.sender, trader, selector, result);
    }
}
