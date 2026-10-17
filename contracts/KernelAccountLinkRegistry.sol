// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @notice Records owner-authorized links between a Moistly/DCC3 identity and a deployed
///         Kernel-style smart account. This contract does not install modules or execute calls.
/// @dev Provider metadata is not proof of account type. Kernel/ERC-7579 classification must be
///      independently verified by the indexer using code, implementation and supported interfaces.
contract KernelAccountLinkRegistry {
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant LINK_TYPEHASH =
        keccak256("KernelAccountLink(address identity,address account,bytes32 providerHash,bool active,uint256 nonce,uint256 deadline)");
    bytes32 private constant NAME_HASH = keccak256("MoistlyKernelAccountLinkRegistry");
    bytes32 private constant VERSION_HASH = keccak256("1");

    struct LinkRecord {
        bytes32 providerHash;
        uint64 updatedAt;
        bool active;
    }

    mapping(address identity => mapping(address account => LinkRecord)) private _links;
    mapping(address identity => mapping(address account => uint256)) public nonces;

    error InvalidAddress();
    error AccountHasNoCode(address account);
    error ExpiredSignature(uint256 deadline);
    error InvalidIdentitySignature(address identity);
    error InvalidAccountSignature(address account);

    event KernelAccountLinked(
        address indexed identity,
        address indexed account,
        bytes32 indexed providerHash,
        bool active,
        uint256 nonce
    );

    /// @notice EIP-712 domain separator bound to this chain and registry.
    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Link or unlink a deployed smart account to a Moistly identity.
    /// @dev Both identity and account must authorize the same chain-bound typed message.
    ///      EOA signatures and ERC-1271 smart-account signatures are supported.
    ///      providerHash should be keccak256(bytes(provider identifier)), e.g. "zerodev".
    function setLink(
        address identity,
        address account,
        bytes32 providerHash,
        bool active,
        uint256 deadline,
        bytes calldata identitySignature,
        bytes calldata accountSignature
    ) external {
        if (identity == address(0) || account == address(0)) revert InvalidAddress();
        if (account.code.length == 0) revert AccountHasNoCode(account);
        if (block.timestamp > deadline) revert ExpiredSignature(deadline);

        uint256 nonce = nonces[identity][account];
        bytes32 structHash = keccak256(
            abi.encode(LINK_TYPEHASH, identity, account, providerHash, active, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));

        if (!SignatureChecker.isValidSignatureNow(identity, digest, identitySignature)) {
            revert InvalidIdentitySignature(identity);
        }
        if (!SignatureChecker.isValidSignatureNow(account, digest, accountSignature)) {
            revert InvalidAccountSignature(account);
        }

        nonces[identity][account] = nonce + 1;
        _links[identity][account] = LinkRecord({
            providerHash: providerHash,
            updatedAt: uint64(block.timestamp),
            active: active
        });

        emit KernelAccountLinked(identity, account, providerHash, active, nonce);
    }

    function getLink(address identity, address account)
        external
        view
        returns (bytes32 providerHash, uint64 updatedAt, bool active)
    {
        LinkRecord storage record = _links[identity][account];
        return (record.providerHash, record.updatedAt, record.active);
    }

    function isLinked(address identity, address account) external view returns (bool) {
        return _links[identity][account].active;
    }
}
