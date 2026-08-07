// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MoistAccountProxy} from "./MoistAccountProxy.sol";

/// @notice CREATE2 factory for deterministic account proxies.
/// @dev Cross-chain address parity requires this factory itself to live at the same address on every
///      target chain and the implementation/initData bytes to be identical. chainid is intentionally
///      excluded from salt derivation.
contract MoistAccountProxyFactory {
    bytes32 public constant DOMAIN_SALT = keccak256("moistly.account.proxy.factory.v1");

    mapping(address accountOwner => uint256 nonce) public nextNonce;
    mapping(bytes32 salt => bool used) public saltUsed;

    error InvalidImplementation();
    error NonceAlreadyConsumed(address owner, uint256 nonce, uint256 nextNonce);
    error DeploymentFailed();

    event AccountProxyDeployed(
        address indexed owner,
        address indexed proxy,
        address indexed implementation,
        uint256 nonce,
        bytes32 salt,
        bytes32 initCodeHash
    );

    /// @notice Derives the canonical CREATE2 salt for an owner/nonce pair.
    function saltFor(address owner, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SALT, owner, nonce));
    }

    /// @notice Returns the exact init-code hash used for CREATE2 prediction/deployment.
    function initCodeHash(address implementation, bytes calldata initData) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(MoistAccountProxy).creationCode, abi.encode(implementation, initData)));
    }

    /// @notice Predicts an account proxy address without mutating nonce state.
    function predictAddress(address owner, uint256 nonce, address implementation, bytes calldata initData)
        public
        view
        returns (address predicted)
    {
        bytes32 salt = saltFor(owner, nonce);
        bytes32 codeHash = initCodeHash(implementation, initData);
        predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    /// @notice Deploy using the caller's next sequential nonce.
    /// @dev The current nonce is consumed atomically only if CREATE2 succeeds.
    function deployNext(address implementation, bytes calldata initData) external payable returns (address proxy) {
        uint256 nonce = nextNonce[msg.sender];
        proxy = _deploy(msg.sender, nonce, implementation, initData, msg.value);
        unchecked {
            nextNonce[msg.sender] = nonce + 1;
        }
    }

    /// @notice Deploy a specific nonce, useful for reproducing a reserved cross-chain account address.
    /// @dev A nonce lower than nextNonce is considered consumed. A higher nonce advances nextNonce after success.
    function deployAtNonce(uint256 nonce, address implementation, bytes calldata initData)
        external
        payable
        returns (address proxy)
    {
        uint256 current = nextNonce[msg.sender];
        if (nonce < current) revert NonceAlreadyConsumed(msg.sender, nonce, current);

        proxy = _deploy(msg.sender, nonce, implementation, initData, msg.value);
        nextNonce[msg.sender] = nonce + 1;
    }

    function _deploy(address owner, uint256 nonce, address implementation, bytes calldata initData, uint256 value)
        private
        returns (address proxy)
    {
        if (implementation == address(0) || implementation.code.length == 0) revert InvalidImplementation();

        bytes32 salt = saltFor(owner, nonce);
        if (saltUsed[salt]) revert NonceAlreadyConsumed(owner, nonce, nextNonce[owner]);

        bytes memory creationCode = abi.encodePacked(
            type(MoistAccountProxy).creationCode,
            abi.encode(implementation, initData)
        );
        bytes32 codeHash = keccak256(creationCode);

        assembly {
            proxy := create2(value, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (proxy == address(0)) revert DeploymentFailed();

        saltUsed[salt] = true;
        emit AccountProxyDeployed(owner, proxy, implementation, nonce, salt, codeHash);
    }
}
