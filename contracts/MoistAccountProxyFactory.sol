// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MoistAccountProxy} from "./MoistAccountProxy.sol";

/// @notice CREATE3 helper whose CREATE2 init code is independent of account init code.
contract MoistCreate3Proxy {
    bool private used;

    error AlreadyUsed();
    error DeploymentFailed();

    function deploy(bytes memory creationCode) external payable returns (address deployed) {
        if (used) revert AlreadyUsed();
        used = true;

        assembly {
            deployed := create(callvalue(), add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }
}

/// @notice CREATE / CREATE2 / CREATE3 factory for account proxies.
/// @dev The logical account-proxy-factory nonce is the canonical account sequence. It is included
///      in every deployment salt/registry id. chainid is intentionally excluded from salt and
///      account-id derivation so identical factory deployments can preserve cross-chain identity.
contract MoistAccountProxyFactory {
    enum DeploymentKind {
        CREATE,
        CREATE2,
        CREATE3
    }

    struct AccountRecord {
        address account;
        address owner;
        address implementation;
        uint256 factoryNonce;
        uint256 chainId;
        DeploymentKind kind;
        bytes32 salt;
        bytes32 initCodeHash;
    }

    bytes32 public constant DOMAIN_SALT = keccak256("moistly.account.proxy.factory.v1");
    bytes32 public constant CREATE_SALT_DOMAIN = keccak256("moistly.account.proxy.factory.create.v1");
    bytes32 public constant CREATE3_SALT_DOMAIN = keccak256("moistly.account.proxy.factory.create3.v1");
    bytes32 public constant ACCOUNT_REGISTRY_DOMAIN = keccak256("moistly.account.registry.v1");

    /// @notice Stable EIP-712 namespace used by the DCC3 verifier. This is intentionally distinct
    ///         from deployment salts; deployment identity must never silently change signature domains.
    bytes32 public constant EIP712_DOMAIN_SALT = keccak256("moistly.dcc3.account.domain.v1");

    mapping(address accountOwner => uint256 nonce) public nextNonce;
    mapping(bytes32 salt => bool used) public saltUsed;
    mapping(address accountOwner => mapping(uint256 nonce => bool used)) public nonceConsumed;

    mapping(bytes32 accountId => AccountRecord record) public accounts;
    mapping(address account => bytes32 accountId) public accountIds;

    error InvalidImplementation();
    error NonceAlreadyConsumed(address owner, uint256 nonce);
    error DeploymentFailed();

    event AccountProxyDeployed(
        address indexed owner,
        address indexed proxy,
        address indexed implementation,
        uint256 nonce,
        bytes32 salt,
        bytes32 initCodeHash
    );

    event AccountRegistered(
        bytes32 indexed accountId,
        address indexed account,
        address indexed owner,
        address implementation,
        uint256 factoryNonce,
        DeploymentKind kind,
        bytes32 salt,
        bytes32 initCodeHash,
        uint256 chainId
    );

    /// @notice Legacy/canonical CREATE2 salt. Kept unchanged for deterministic compatibility.
    function saltFor(address owner, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SALT, owner, nonce));
    }

    /// @notice Canonical nonce-derived salt for each deployment mode.
    /// @dev For CREATE this is a registry/provenance salt only; CREATE addresses themselves are nonce-based.
    function saltForKind(address owner, uint256 nonce, DeploymentKind kind) public pure returns (bytes32) {
        if (kind == DeploymentKind.CREATE2) return saltFor(owner, nonce);
        if (kind == DeploymentKind.CREATE3) {
            return keccak256(abi.encode(CREATE3_SALT_DOMAIN, owner, nonce));
        }
        return keccak256(abi.encode(CREATE_SALT_DOMAIN, owner, nonce));
    }

    /// @notice Chain-agnostic identity for one logical account incarnation.
    function accountIdFor(address owner, uint256 nonce, DeploymentKind kind) public view returns (bytes32) {
        return keccak256(
            abi.encode(ACCOUNT_REGISTRY_DOMAIN, address(this), owner, nonce, kind, saltForKind(owner, nonce, kind))
        );
    }

    function nonceUsed(address owner, uint256 nonce) public view returns (bool) {
        return nonceConsumed[owner][nonce] || saltUsed[saltFor(owner, nonce)];
    }

    function initCodeHash(address implementation, bytes calldata initData) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(MoistAccountProxy).creationCode, abi.encode(implementation, initData)));
    }

    /// @notice Existing CREATE2 predictor retained for compatibility.
    function predictAddress(address owner, uint256 nonce, address implementation, bytes calldata initData)
        public
        view
        returns (address predicted)
    {
        bytes32 salt = saltFor(owner, nonce);
        bytes32 codeHash = initCodeHash(implementation, initData);
        predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    /// @notice Predict CREATE3 address. Unlike CREATE2 this does not depend on implementation/initData.
    function predictCreate3Address(address owner, uint256 nonce) public view returns (address predicted) {
        bytes32 salt = saltForKind(owner, nonce, DeploymentKind.CREATE3);
        bytes32 proxyCodeHash = keccak256(type(MoistCreate3Proxy).creationCode);
        address create3Proxy = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, proxyCodeHash))))
        );

        // First CREATE from a newly-created contract uses nonce 1.
        predicted = address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", create3Proxy, hex"01")))));
    }

    /// @notice Existing sequential path remains CREATE2 for backwards compatibility.
    function deployNext(address implementation, bytes calldata initData) external payable returns (address proxy) {
        uint256 nonce = _nextFreeNonce(msg.sender, nextNonce[msg.sender]);
        proxy = _deployCreate2(msg.sender, nonce, implementation, initData, msg.value);
        nextNonce[msg.sender] = _nextFreeNonce(msg.sender, nonce + 1);
    }

    /// @notice Existing explicit path remains CREATE2 for backwards compatibility.
    function deployAtNonce(uint256 nonce, address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        proxy = _deployCreate2(msg.sender, nonce, implementation, initData, msg.value);
        _advanceIfCurrent(msg.sender, nonce);
    }

    function deployCreateNext(address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        uint256 nonce = _nextFreeNonce(msg.sender, nextNonce[msg.sender]);
        proxy = _deployCreate(msg.sender, nonce, implementation, initData, msg.value);
        nextNonce[msg.sender] = _nextFreeNonce(msg.sender, nonce + 1);
    }

    function deployCreateAtNonce(uint256 nonce, address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        proxy = _deployCreate(msg.sender, nonce, implementation, initData, msg.value);
        _advanceIfCurrent(msg.sender, nonce);
    }

    function deployCreate3Next(address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        uint256 nonce = _nextFreeNonce(msg.sender, nextNonce[msg.sender]);
        proxy = _deployCreate3(msg.sender, nonce, implementation, initData, msg.value);
        nextNonce[msg.sender] = _nextFreeNonce(msg.sender, nonce + 1);
    }

    function deployCreate3AtNonce(uint256 nonce, address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        proxy = _deployCreate3(msg.sender, nonce, implementation, initData, msg.value);
        _advanceIfCurrent(msg.sender, nonce);
    }

    function _advanceIfCurrent(address owner, uint256 nonce) private {
        if (nonce == nextNonce[owner]) {
            nextNonce[owner] = _nextFreeNonce(owner, nonce + 1);
        }
    }

    function _nextFreeNonce(address owner, uint256 cursor) private view returns (uint256) {
        while (nonceUsed(owner, cursor)) {
            unchecked {
                ++cursor;
            }
        }
        return cursor;
    }

    function _creationCode(address implementation, bytes calldata initData)
        private
        view
        returns (bytes memory creationCode, bytes32 codeHash)
    {
        if (implementation == address(0) || implementation.code.length == 0) revert InvalidImplementation();
        creationCode = abi.encodePacked(type(MoistAccountProxy).creationCode, abi.encode(implementation, initData));
        codeHash = keccak256(creationCode);
    }

    function _reserveNonce(address owner, uint256 nonce, DeploymentKind kind) private returns (bytes32 salt) {
        if (nonceUsed(owner, nonce)) revert NonceAlreadyConsumed(owner, nonce);
        nonceConsumed[owner][nonce] = true;
        salt = saltForKind(owner, nonce, kind);
        if (saltUsed[salt]) revert NonceAlreadyConsumed(owner, nonce);
        saltUsed[salt] = true;
    }

    function _deployCreate2(
        address owner,
        uint256 nonce,
        address implementation,
        bytes calldata initData,
        uint256 value
    ) private returns (address proxy) {
        (bytes memory creationCode, bytes32 codeHash) = _creationCode(implementation, initData);
        bytes32 salt = _reserveNonce(owner, nonce, DeploymentKind.CREATE2);

        assembly {
            proxy := create2(value, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (proxy == address(0)) revert DeploymentFailed();

        emit AccountProxyDeployed(owner, proxy, implementation, nonce, salt, codeHash);
        _register(owner, proxy, implementation, nonce, DeploymentKind.CREATE2, salt, codeHash);
    }

    function _deployCreate(
        address owner,
        uint256 nonce,
        address implementation,
        bytes calldata initData,
        uint256 value
    ) private returns (address proxy) {
        (bytes memory creationCode, bytes32 codeHash) = _creationCode(implementation, initData);
        bytes32 salt = _reserveNonce(owner, nonce, DeploymentKind.CREATE);

        assembly {
            proxy := create(value, add(creationCode, 0x20), mload(creationCode))
        }
        if (proxy == address(0)) revert DeploymentFailed();

        _register(owner, proxy, implementation, nonce, DeploymentKind.CREATE, salt, codeHash);
    }

    function _deployCreate3(
        address owner,
        uint256 nonce,
        address implementation,
        bytes calldata initData,
        uint256 value
    ) private returns (address proxy) {
        (bytes memory creationCode, bytes32 codeHash) = _creationCode(implementation, initData);
        bytes32 salt = _reserveNonce(owner, nonce, DeploymentKind.CREATE3);

        MoistCreate3Proxy create3Proxy = new MoistCreate3Proxy{salt: salt}();
        proxy = create3Proxy.deploy{value: value}(creationCode);
        if (proxy == address(0)) revert DeploymentFailed();

        _register(owner, proxy, implementation, nonce, DeploymentKind.CREATE3, salt, codeHash);
    }

    function _register(
        address owner,
        address account,
        address implementation,
        uint256 nonce,
        DeploymentKind kind,
        bytes32 salt,
        bytes32 codeHash
    ) private {
        bytes32 accountId = accountIdFor(owner, nonce, kind);
        accounts[accountId] = AccountRecord({
            account: account,
            owner: owner,
            implementation: implementation,
            factoryNonce: nonce,
            chainId: block.chainid,
            kind: kind,
            salt: salt,
            initCodeHash: codeHash
        });
        accountIds[account] = accountId;

        emit AccountRegistered(
            accountId,
            account,
            owner,
            implementation,
            nonce,
            kind,
            salt,
            codeHash,
            block.chainid
        );
    }
}
