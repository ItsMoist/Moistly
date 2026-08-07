// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC173 {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

/// @title Moist7702Verifier173
/// @notice EIP-7702 delegate implementation bound to the canonical DCC3 EOA.
/// @dev In delegated execution address(this) is DCC3, so DCC3 itself is the EIP-712
///      verifyingContract. The domain salt is a stable signature namespace and is
///      deliberately distinct from CREATE/CREATE2/CREATE3 deployment salts.
contract Moist7702Verifier173 is IERC173, IERC165, IERC1271 {
    address public constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;

    bytes4 public constant ERC173_INTERFACE_ID = 0x7f5828d0;
    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 public constant ERC1271_MAGICVALUE = 0x1626ba7e;

    bytes32 public constant EIP712_DOMAIN_SALT = keccak256("moistly.dcc3.account.domain.v1");

    uint256 private constant SECP256K1N_HALF =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    bytes32 private constant OWNER_SLOT =
        bytes32(uint256(keccak256("moistly.erc7702.eip173.owner.v1")) - 1);

    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
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

    function owner() external view override returns (address) {
        return _owner();
    }

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

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == ERC173_INTERFACE_ID || interfaceId == ERC165_INTERFACE_ID;
    }

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

    function isCanonicalDCC3Context() external view returns (bool) {
        return address(this) == DCC3;
    }

    /// @notice Canonical EIP-712 domain separator for the current chain.
    /// @dev In the production 7702 context verifyingContract is exactly DCC3.
    function domainSeparatorV4() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this),
                EIP712_DOMAIN_SALT
            )
        );
    }

    /// @notice Exposes all canonical domain fields for indexers and cross-chain checks.
    function eip712Domain()
        external
        view
        returns (
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            bytes32 separator
        )
    {
        return (
            "Moist7702Verifier",
            "1",
            block.chainid,
            address(this),
            EIP712_DOMAIN_SALT,
            domainSeparatorV4()
        );
    }

    function hashTypedDataV4(bytes32 structHash)
        external
        view
        onlyCanonicalContext
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparatorV4(), structHash));
    }

    function ownerStorageSlot() external pure returns (bytes32) {
        return OWNER_SLOT;
    }

    function _owner() internal view returns (address currentOwner) {
        bytes32 slot = OWNER_SLOT;
        assembly {
            currentOwner := sload(slot)
        }
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
