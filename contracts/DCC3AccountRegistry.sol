// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Registry for deterministic DCC3 account identity metadata.
/// @dev It records identity and expected storage conventions. Live balances and code are read
///      directly from each chain; they are deliberately not mirrored as trusted registry state.
contract DCC3AccountRegistry {
    bytes32 public constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct AccountIdentity {
        address account;
        address delegatedImplementation;
        address deterministicFactory;
        bytes32 factorySalt;
        bytes32 initCodeHash;
        bytes32 delegatedStorageSlot;
        bool active;
    }

    address public owner;
    mapping(bytes32 accountId => AccountIdentity) private _accounts;

    error Unauthorized(address caller);
    error InvalidAddress();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AccountIdentityUpdated(
        bytes32 indexed accountId,
        address indexed account,
        address indexed delegatedImplementation,
        address deterministicFactory,
        bytes32 factorySalt,
        bytes32 initCodeHash,
        bytes32 delegatedStorageSlot,
        bool active
    );

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice EIP-173 ownership transfer.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    /// @notice Stable identifier independent of chain ID.
    function accountId(address account, address deterministicFactory, bytes32 factorySalt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(account, deterministicFactory, factorySalt));
    }

    function setAccountIdentity(AccountIdentity calldata identity) external onlyOwner returns (bytes32 id) {
        if (identity.account == address(0) || identity.delegatedImplementation == address(0)) {
            revert InvalidAddress();
        }
        id = accountId(identity.account, identity.deterministicFactory, identity.factorySalt);
        _accounts[id] = identity;
        emit AccountIdentityUpdated(
            id,
            identity.account,
            identity.delegatedImplementation,
            identity.deterministicFactory,
            identity.factorySalt,
            identity.initCodeHash,
            identity.delegatedStorageSlot,
            identity.active
        );
    }

    function getAccountIdentity(bytes32 id) external view returns (AccountIdentity memory) {
        return _accounts[id];
    }

    /// @notice Expected EIP-7702 delegation designator for an implementation.
    function delegationDesignator(address implementation) external pure returns (bytes memory) {
        return abi.encodePacked(hex"ef0100", implementation);
    }

    /// @notice Utility for monitors: ERC-20 balanceOf calldata for an account.
    function balanceOfCalldata(address account) external pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(0x70a08231), account);
    }
}
