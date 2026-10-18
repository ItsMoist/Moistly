// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {KernelAccountLinkRegistry} from "../contracts/KernelAccountLinkRegistry.sol";

contract Mock1271Account {
    address public immutable signer;
    bytes4 private constant MAGIC = 0x1626ba7e;

    constructor(address signer_) {
        signer = signer_;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (signature.length != 65) return 0xffffffff;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s) == signer ? MAGIC : bytes4(0xffffffff);
    }
}

contract KernelAccountLinkRegistryTest is Test {
    KernelAccountLinkRegistry registry;
    uint256 identityKey = 0xA11CE;
    uint256 accountOwnerKey = 0xB0B;
    address identity;
    Mock1271Account account;
    bytes32 providerHash = keccak256("zerodev");

    function setUp() public {
        registry = new KernelAccountLinkRegistry();
        identity = vm.addr(identityKey);
        account = new Mock1271Account(vm.addr(accountOwnerKey));
    }

    function _signature(uint256 key, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _link(bool active, uint256 deadline) internal {
        bytes32 digest = _digest(identity, address(account), providerHash, active, 0, deadline);
        registry.setLink(
            identity,
            address(account),
            providerHash,
            active,
            deadline,
            _signature(identityKey, digest),
            _signature(accountOwnerKey, digest)
        );
    }

    function _digest(
        address identity_,
        address account_,
        bytes32 providerHash_,
        bool active,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("KernelAccountLink(address identity,address account,bytes32 providerHash,bool active,uint256 nonce,uint256 deadline)"),
                identity_, account_, providerHash_, active, nonce, deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
    }

    function test_LinkRequiresBothValidSignatures() public {
        uint256 deadline = block.timestamp + 1 days;
        _link(true, deadline);
        (bytes32 provider, uint64 updatedAt, bool active) = registry.getLink(identity, address(account));
        assertEq(provider, providerHash);
        assertEq(updatedAt, uint64(block.timestamp));
        assertTrue(active);
        assertEq(registry.nonces(identity, address(account)), 1);
    }

    function test_UnlinkRequiresNextNonce() public {
        uint256 deadline = block.timestamp + 1 days;
        _link(true, deadline);
        bytes32 digest = _digest(identity, address(account), providerHash, false, 1, deadline);
        registry.setLink(identity, address(account), providerHash, false, deadline,
            _signature(identityKey, digest), _signature(accountOwnerKey, digest));
        assertFalse(registry.isLinked(identity, address(account)));
        assertEq(registry.nonces(identity, address(account)), 2);
    }

    function test_ReplayFailsBecauseNonceAdvanced() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _digest(identity, address(account), providerHash, true, 0, deadline);
        bytes memory identitySig = _signature(identityKey, digest);
        bytes memory accountSig = _signature(accountOwnerKey, digest);
        registry.setLink(identity, address(account), providerHash, true, deadline, identitySig, accountSig);
        vm.expectRevert(KernelAccountLinkRegistry.InvalidIdentitySignature.selector);
        registry.setLink(identity, address(account), providerHash, true, deadline, identitySig, accountSig);
    }

    function test_ExpiredSignatureFails() public {
        uint256 deadline = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(KernelAccountLinkRegistry.ExpiredSignature.selector, deadline));
        _link(true, deadline);
    }

    function test_WrongChainDomainInvalidatesSignatures() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _digest(identity, address(account), providerHash, true, 0, deadline);
        bytes memory identitySig = _signature(identityKey, digest);
        bytes memory accountSig = _signature(accountOwnerKey, digest);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(KernelAccountLinkRegistry.InvalidIdentitySignature.selector);
        registry.setLink(identity, address(account), providerHash, true, deadline, identitySig, accountSig);
    }

    function test_RejectsAccountWithoutCode() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.expectRevert(abi.encodeWithSelector(KernelAccountLinkRegistry.AccountHasNoCode.selector, address(0x1234)));
        registry.setLink(identity, address(0x1234), providerHash, true, deadline, bytes(""), bytes(""));
    }
}
