// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MoistSafeGuard, ISafeTransactionGuard} from "../../contracts/MoistSafeGuard.sol";
import {Moist7702Verifier173} from "../../contracts/Moist7702Verifier173.sol";
import {CoinbaseSmartWalletValidator} from "../../src/validators/CoinbaseSmartWalletValidator.sol";

interface Vm {
    function etch(address, bytes calldata) external;
    function prank(address) external;
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function addr(uint256) external returns (address);
    function expectRevert(bytes calldata) external;
    function expectRevert() external;
}

interface WalletFactory {
    function createAccount(bytes[] calldata owners, uint256 nonce) external returns (address);
}

interface Wallet {
    function replaySafeHash(bytes32 digest) external view returns (bytes32);
}

abstract contract SignatureFixture {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes4 constant VALID = 0x1626ba7e;
    bytes32 constant DIGEST = keccak256("Moistly test message");
    uint256 constant TEST_KEY = 12345;

    function signDigest(bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
}

contract SafeGuardTest {
    function testBlocksModuleGuardChangeAndAllowsOrdinaryCall() public {
        MoistSafeGuard guard = new MoistSafeGuard(address(this));
        check(guard, address(123), "");
        // Encode independently of the production interface so an ABI typo fails the test.
        bytes memory data = abi.encodeWithSignature("setModuleGuard(address)", address(42));
        Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).expectRevert(
            abi.encodeWithSelector(MoistSafeGuard.SafeConfigurationBlocked.selector, bytes4(data))
        );
        check(guard, address(this), data);
    }

    function check(MoistSafeGuard guard, address target, bytes memory data) internal view {
        guard.checkTransaction(target, 0, data, ISafeTransactionGuard.Operation.Call,
            0, 0, 0, address(0), payable(address(0)), "", address(this));
    }
}

contract VerifierTest is SignatureFixture {
    function testSignatureChecksInCanonicalContext() public {
        Moist7702Verifier173 implementation = new Moist7702Verifier173();
        address account = implementation.DCC3();
        vm.etch(account, address(implementation).code);
        Moist7702Verifier173 verifier = Moist7702Verifier173(account);
        require(verifier.owner() == account);
        address owner = vm.addr(TEST_KEY);
        vm.prank(account);
        verifier.transferOwnership(owner);
        bytes32 hash = verifier.hashTypedDataV4(DIGEST);
        bytes memory sig = signDigest(hash);
        require(verifier.isValidSignature(hash, sig) == VALID);
        require(verifier.isValidSignature(DIGEST, sig) != VALID);
        require(implementation.isValidSignature(hash, sig) != VALID);
    }
}

contract CoinbaseValidatorForkTest is SignatureFixture {
    struct SignatureWrapper {
        uint256 ownerIndex;
        bytes signatureData;
    }

    function testDeployedWalletAcceptsOwnerAndRejectsInvalidSignatures() public {
        require(block.chainid == 1);
        WalletFactory factory = WalletFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(vm.addr(TEST_KEY));
        address wallet = factory.createAccount(owners, uint256(keccak256("Moistly fixture")));
        CoinbaseSmartWalletValidator validator = new CoinbaseSmartWalletValidator(wallet);
        bytes memory sig = abi.encode(SignatureWrapper(0, signDigest(Wallet(wallet).replaySafeHash(DIGEST))));
        require(validator.isValidSignature(DIGEST, sig) == VALID);
        vm.expectRevert(abi.encodeWithSelector(CoinbaseSmartWalletValidator.InvalidWalletSignature.selector));
        validator.isValidSignature(bytes32(uint256(1)), sig);
        vm.expectRevert();
        validator.isValidSignature(DIGEST, hex"01");
    }
}
