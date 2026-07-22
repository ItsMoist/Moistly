
/** 
 *  SourceUnit: /Users/bnelligan/DAPP/Moistly/contracts/OFTWrapper.sol
*/

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.28;

/// @dev Interface for the underlying OFT token
interface IOFT {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice ERC20 wrapper around an Omni Function Token (OFT)
/// @dev This contract wraps an underlying OFT token and provides a proxy-compatible initializer.
///      It delegates all ERC20 operations to the underlying token.
contract OFTWrapper {
    // Immutable reference to the underlying OFT token
    IOFT public immutable underlyingToken;
    
    // Proxy owner (can be set during initialization)
    address private _proxyOwner;
    
    // Event for initialization
    event Initialized(address indexed proxyOwner, address indexed underlyingToken);

    /// @notice Constructor sets the underlying token address
    /// @param _underlyingToken The address of the OFT token to wrap
    constructor(address _underlyingToken) {
        require(_underlyingToken != address(0), "Invalid token address");
        underlyingToken = IOFT(_underlyingToken);
    }

    /// @notice Initialize the wrapper with a proxy owner
    /// @param owner The address that will own the proxy
    function initialize(address owner) external {
        require(_proxyOwner == address(0), "Already initialized");
        require(owner != address(0), "Invalid proxy owner");
        _proxyOwner = owner;
        emit Initialized(owner, address(underlyingToken));
    }

    /// @notice Alternative initializer for proxy compatibility
    function initializeProxyOwner() external {
        require(_proxyOwner == address(0), "Already initialized");
        _proxyOwner = msg.sender;
        emit Initialized(msg.sender, address(underlyingToken));
    }

    /// @notice Get the proxy owner
    function proxyOwner() external view returns (address) {
        return _proxyOwner;
    }

    // ============ ERC20 Delegation ============

    /// @notice Get token name
    function name() external view returns (string memory) {
        return underlyingToken.name();
    }

    /// @notice Get token symbol
    function symbol() external view returns (string memory) {
        return underlyingToken.symbol();
    }

    /// @notice Get token decimals
    function decimals() external view returns (uint8) {
        return underlyingToken.decimals();
    }

    /// @notice Get total token supply
    function totalSupply() external view returns (uint256) {
        return underlyingToken.totalSupply();
    }

    /// @notice Get balance of an account
    function balanceOf(address account) external view returns (uint256) {
        return underlyingToken.balanceOf(account);
    }

    /// @notice Get allowance from owner to spender
    function allowance(address owner, address spender) external view returns (uint256) {
        return underlyingToken.allowance(owner, spender);
    }

    /// @notice Approve spender to transfer tokens
    function approve(address spender, uint256 amount) external returns (bool) {
        return underlyingToken.approve(spender, amount);
    }

    /// @notice Transfer tokens to recipient
    function transfer(address to, uint256 amount) external returns (bool) {
        return underlyingToken.transfer(to, amount);
    }

    /// @notice Transfer tokens from sender to recipient
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return underlyingToken.transferFrom(from, to, amount);
    }
}

