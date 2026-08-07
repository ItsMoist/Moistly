// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDurinL2RegistryOwner {
    function owner(bytes32 node) external view returns (address);
}

contract L2AccountRegistry {
    enum DeploymentKind { CREATE, CREATE2, CREATE3 }

    struct AccountRecord {
        bytes32 accountId;
        address factory;
        address account;
        address owner;
        address implementation;
        address verifier;
        uint256 chainId;
        uint256 factoryNonce;
        DeploymentKind kind;
        bytes32 deploymentSalt;
        bytes32 initCodeHash;
    }

    bytes32 public constant ACCOUNT_REGISTRY_DOMAIN = keccak256("moistly.account.registry.v1");

    IDurinL2RegistryOwner public immutable l2Registry;
    mapping(bytes32 => AccountRecord) public accounts;
    mapping(bytes32 => bytes32[]) private _nodeAccounts;
    mapping(bytes32 => mapping(bytes32 => bool)) public nodeHasAccount;
    mapping(bytes32 => bytes32) public primaryAccountId;

    event AccountLinked(bytes32 indexed node, bytes32 indexed accountId, address indexed account, address factory, uint256 factoryNonce, DeploymentKind kind, uint256 chainId);
    event PrimaryAccountSet(bytes32 indexed node, bytes32 indexed accountId, address indexed account);

    error UnauthorizedNode(bytes32 node, address caller);
    error InvalidAccountId(bytes32 supplied, bytes32 expected);
    error AlreadyLinked(bytes32 node, bytes32 accountId);
    error AccountNotLinked(bytes32 node, bytes32 accountId);
    error ZeroAddress();

    constructor(address registry_) {
        if (registry_ == address(0)) revert ZeroAddress();
        l2Registry = IDurinL2RegistryOwner(registry_);
    }

    modifier onlyNodeOwner(bytes32 node) {
        if (l2Registry.owner(node) != msg.sender) revert UnauthorizedNode(node, msg.sender);
        _;
    }

    function deriveAccountId(address factory, address owner_, uint256 factoryNonce, DeploymentKind kind, bytes32 deploymentSalt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(ACCOUNT_REGISTRY_DOMAIN, factory, owner_, factoryNonce, kind, deploymentSalt));
    }

    function linkAccount(bytes32 node, AccountRecord calldata record) external onlyNodeOwner(node) {
        if (record.factory == address(0) || record.account == address(0) || record.owner == address(0) || record.implementation == address(0) || record.verifier == address(0)) revert ZeroAddress();

        bytes32 expected = deriveAccountId(record.factory, record.owner, record.factoryNonce, record.kind, record.deploymentSalt);
        if (record.accountId != expected) revert InvalidAccountId(record.accountId, expected);
        if (nodeHasAccount[node][record.accountId]) revert AlreadyLinked(node, record.accountId);

        AccountRecord storage existing = accounts[record.accountId];
        if (existing.account == address(0)) {
            accounts[record.accountId] = record;
        } else if (
            existing.factory != record.factory || existing.account != record.account || existing.owner != record.owner ||
            existing.implementation != record.implementation || existing.verifier != record.verifier ||
            existing.chainId != record.chainId || existing.factoryNonce != record.factoryNonce || existing.kind != record.kind ||
            existing.deploymentSalt != record.deploymentSalt || existing.initCodeHash != record.initCodeHash
        ) {
            revert InvalidAccountId(record.accountId, expected);
        }

        nodeHasAccount[node][record.accountId] = true;
        _nodeAccounts[node].push(record.accountId);
        emit AccountLinked(node, record.accountId, record.account, record.factory, record.factoryNonce, record.kind, record.chainId);

        if (primaryAccountId[node] == bytes32(0)) {
            primaryAccountId[node] = record.accountId;
            emit PrimaryAccountSet(node, record.accountId, record.account);
        }
    }

    function setPrimaryAccount(bytes32 node, bytes32 accountId) external onlyNodeOwner(node) {
        if (!nodeHasAccount[node][accountId]) revert AccountNotLinked(node, accountId);
        primaryAccountId[node] = accountId;
        emit PrimaryAccountSet(node, accountId, accounts[accountId].account);
    }

    function accountIdsForNode(bytes32 node) external view returns (bytes32[] memory) {
        return _nodeAccounts[node];
    }

    function primaryAccount(bytes32 node) external view returns (AccountRecord memory) {
        return accounts[primaryAccountId[node]];
    }
}
