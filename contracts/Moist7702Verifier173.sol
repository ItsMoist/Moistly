// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC-173 ownership interface.
interface IERC173 {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/// @notice Minimal ERC-165 interface used for ERC-173 discovery.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice ERC-1271 contract-signature verification interface.
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

/// @title Moist7702Verifier173
/// @notice EIP-7702 delegate implementation bound to the canonical DCC3 EOA.
/// @dev When this code is executed through EIP-7702 delegation, address(this) is
///      the delegating EOA. Therefore the EIP-712 verifyingContract is DCC3 itself,
///      not this implementation contract's deployment address.
contract Moist7702Verifier173 is IERC173, IERC165, IERC1271 {
    /// @notice Canonical DCC3 EOA that is permitted to use this implementation as
    ///         the production verification surface.
    address public constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;

    /// @notice ERC-173 interface id: owner() ^ transferOwnership(address).
    bytes4 public constant ERC173_INTERFACE_ID = 0x7f5828d0;

    /// @notice ERC-165 interface id.
    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @notice ERC-1271 success magic value.
    bytes4 public constant ERC1271_MAGICVALUE = 0x1626ba7e;

    /// @dev secp256k1n / 2, used to reject malleable high-s signatures.
    uint256 private constant SECP256K1N_HALF =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    /// @dev Namespaced ownership slot to avoid collisions with other delegated,
    ///      proxy, Safe, or account-abstraction storage layouts.
    bytes32 private constant OWNER_SLOT =
        bytes32(uint256(keccak256("moistly.erc7702.eip173.owner.v1")) - 1);

    /// @dev EIP-712 type hashes. The domain deliberately uses address(this), which
    ///      equals DCC3 in the canonical EIP-7702 execution context.
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant NAME_HASH = keccak256("Moist7702Verifier");
    bytes32 private constant VERSION_HASH = keccak256("1");

    error NotCanonicalDCC3Context(address context);
    error NotOwner(address caller);
    error ZeroAddressOwner();

    modifier onlyCanonicalContext() {
        if (address(this) != DCC3) revert NotCanonicalDCC3Context(address(this));
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner()) revert NotOwner(msg.sender);
        _;
    }

    /// @notice Returns the current ERC-173 owner.
    /// @dev Before a transfer is persisted, DCC3 is the default owner. This avoids
    ///      requiring an initializer transaction solely to establish canonical
    ///      ownership after the 7702 authorization is installed.
    function owner() external view override returns (address) {
        return _owner();
    }

    /// @notice Transfers ERC-173 ownership in DCC3's delegated storage context.
    /// @dev This can only mutate ownership while executing as DCC3 via EIP-7702.
    function transferOwnership(address newOwner)
        external
        override
        onlyCanonicalContext
        onlyOwner
    {
        if (newOwner == address(0)) revert ZeroAddressOwner();

        address previousOwner = _owner();
        bytes32 slot = OWNER_SLOT;
        assembly {
            sstore(slot, newOwner)
        }

        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice ERC-165 discovery for ERC-173.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == ERC173_INTERFACE_ID || interfaceId == ERC165_INTERFACE_ID;
    }

    /// @notice ERC-1271 signature validation for the DCC3 7702 account.
    /// @dev Validation only succeeds while executing in DCC3's delegated context,
    ///      and the recovered signer must equal the current ERC-173 owner.
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        if (address(this) != DCC3) return bytes4(0xffffffff);
        if (_recover(hash, signature) != _owner()) return bytes4(0xffffffff);
        return ERC1271_MAGICVALUE;
    }

    /// @notice True only when the code is executing in the canonical DCC3 7702 context.
    function isCanonicalDCC3Context() external view returns (bool) {
        return address(this) == DCC3;
    }

    /// @notice Returns the EIP-712 domain separator for the current execution context.
    /// @dev In the valid EIP-7702 context, verifyingContract == DCC3.
    function domainSeparatorV4() public view returns (bytes32) {
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

    /// @notice Builds an EIP-712 digest while enforcing the DCC3 verification surface.
    function hashTypedDataV4(bytes32 structHash)
        external
        view
        onlyCanonicalContext
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparatorV4(), structHash));
    }

    /// @notice Exposes the namespaced owner slot for cross-chain/account monitoring.
    function ownerStorageSlot() external pure returns (bytes32) {
        return OWNER_SLOT;
    }

    function _owner() internal view returns (address currentOwner) {
        bytes32 slot = OWNER_SLOT;
        assembly {
            currentOwner := sload(slot)
        }

        // DCC3 remains the canonical ERC-173 owner until an explicit transfer is
        // made in DCC3's delegated storage context.
        if (currentOwner == address(0)) currentOwner = DCC3;
    }

    function _recover(bytes32 hash, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (uint256(s) > SECP256K1N_HALF) return address(0);
        if (v != 27 && v != 28) return address(0);

        signer = ecrecover(hash, v, r, s);
    }
}
