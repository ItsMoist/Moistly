// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

interface IEntryPointV07 {
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
}

interface IKernelRecovery {
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable;
}

interface IRoleBasedValidator {
    function rotateCosignerWithAdmin(address newCosigner) external;
    function getUserAdmin(address account) external view returns (address);
    function getCosigner(address account) external view returns (address);
    function getRotatingCosignerUntil(address account) external view returns (uint256);
}

interface ICosigningModuleV2 {
    function triggerSlowWithdraw(bytes32 id, address wallet) external;
    function remainingSlowWithdrawTime(address wallet) external view returns (uint256);
    function signers(address wallet, bytes32 id) external view returns (address);
}

abstract contract ProviderFreeKernelRecoveryBase is Script {
    struct Execution {
        address target;
        uint256 value;
        bytes callData;
    }

    address internal constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address internal constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;
    bytes32 internal constant MODE_SINGLE = bytes32(0);
    bytes32 internal constant MODE_BATCH = bytes32(uint256(1) << 248);

    error WrongSigner(address expected, address actual);
    error UnsupportedChain(uint256 chainId);
    error ERC1155NotSupportedByDCC3();
    error NothingToSweep();

    function _privateKey(string memory envName, address expected) internal returns (uint256 key) {
        key = vm.envUint(envName);
        address actual = vm.addr(key);
        if (actual != expected) revert WrongSigner(expected, actual);
    }

    function _op(address account, uint256 nonce, bytes memory callData)
        internal
        pure
        returns (PackedUserOperation memory op)
    {
        op.sender = account;
        op.nonce = nonce;
        op.callData = callData;
        op.accountGasLimits = bytes32((uint256(1_500_000) << 128) | uint256(3_000_000));
        op.preVerificationGas = 100_000;
        // Deliberately zero: this script calls handleOps directly, so the broadcasting EOA pays gas.
        // The account therefore owes no EntryPoint prefund and its full native balance can be swept.
        op.gasFees = bytes32(0);
    }

    function _singleCall(address target, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeCall(IKernelRecovery.execute, (MODE_SINGLE, abi.encodePacked(target, value, data)));
    }

    function _batchCall(Execution[] memory calls) internal pure returns (bytes memory) {
        return abi.encodeCall(IKernelRecovery.execute, (MODE_BATCH, abi.encode(calls)));
    }

    function _sig(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _send(PackedUserOperation[] memory ops, uint256 broadcasterKey) internal {
        address beneficiary = vm.addr(broadcasterKey);
        vm.startBroadcast(broadcasterKey);
        IEntryPointV07(ENTRY_POINT).handleOps(ops, payable(beneficiary));
        vm.stopBroadcast();
    }

    function _extraERC20s() internal view returns (address[] memory) {
        return vm.envOr("EXTRA_ERC20S", ",", new address[](0));
    }

    function _erc721s() internal view returns (address[] memory tokens, uint256[] memory ids) {
        tokens = vm.envOr("ERC721_TOKENS", ",", new address[](0));
        ids = vm.envOr("ERC721_IDS", ",", new uint256[](0));
        require(tokens.length == ids.length, "ERC721 token/id length mismatch");
    }

    /// @dev ERC-20 transfers first, then ERC-721 `transferFrom` (DCC3 has no onERC721Received), then all native ETH.
    function _orderedCalls(address account, address[] memory erc20s) internal view returns (Execution[] memory calls) {
        (address[] memory nftTokens, uint256[] memory nftIds) = _erc721s();
        uint256 count = nftTokens.length + (account.balance == 0 ? 0 : 1);
        for (uint256 i; i < erc20s.length; ++i) {
            if (IERC20(erc20s[i]).balanceOf(account) != 0) ++count;
        }
        calls = new Execution[](count);
        uint256 n;
        for (uint256 i; i < erc20s.length; ++i) {
            uint256 balance = IERC20(erc20s[i]).balanceOf(account);
            if (balance != 0) calls[n++] = Execution(erc20s[i], 0, abi.encodeCall(IERC20.transfer, (DCC3, balance)));
        }
        for (uint256 i; i < nftTokens.length; ++i) {
            calls[n++] = Execution(nftTokens[i], 0, abi.encodeCall(IERC721.transferFrom, (account, DCC3, nftIds[i])));
        }
        if (account.balance != 0) calls[n] = Execution(DCC3, account.balance, "");
    }

    function _rejectERC1155s() internal view {
        address[] memory tokens = vm.envOr("ERC1155_TOKENS", ",", new address[](0));
        if (tokens.length != 0) revert ERC1155NotSupportedByDCC3();
    }
}

abstract contract RoleBasedKernelBase is ProviderFreeKernelRecoveryBase {
    address constant ACCOUNT = 0x0A6aa42783756Dd3755a80df8F641Aa4F16C7F2C;
    address constant VALIDATOR = 0xA24bD06230f3F54e5bf266AE7A41750eE3b789FA;

    struct SignatureWithExpiry {
        uint256 validUntil;
        uint256 validAfter;
        bytes signature;
    }

    function _sendRoleBased(uint256 key, bytes memory callData) internal {
        uint256 nonce = IEntryPointV07(ENTRY_POINT).getNonce(ACCOUNT, 0);
        PackedUserOperation memory op = _op(ACCOUNT, nonce, callData);
        op.signature = _roleBasedSignature(key, IEntryPointV07(ENTRY_POINT).getUserOpHash(op));
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        _send(ops, key);
    }

    /// @dev RoleBasedECDSAValidator signs EIP-712 Approve(keccak256(userOpHash, validUntil, validAfter)).
    ///      validUntil/validAfter are compared with block.number, so the window is left open.
    function _roleBasedSignature(uint256 key, bytes32 userOpHash) internal view returns (bytes memory) {
        uint256 validUntil = type(uint256).max;
        bytes32 hashToSign = keccak256(abi.encode(userOpHash, validUntil, uint256(0)));
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("RoleBasedECDSAValidator"),
                keccak256("1.4.3"),
                block.chainid,
                VALIDATOR
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domain,
                keccak256(abi.encode(keccak256("Approve(bytes32 callDataAndNonceHash)"), hashToSign))
            )
        );
        SignatureWithExpiry[] memory signatures = new SignatureWithExpiry[](1);
        signatures[0] = SignatureWithExpiry(validUntil, 0, _sig(key, digest));
        return abi.encode(bytes32(0), new bytes32[](0), signatures);
    }
}

/// @notice Starts the 24-hour provider-free recovery for 0x0A6a... on the current chain by making the
///         admin key (0xA15C...) the cosigner. Run once on Arbitrum, Base, and Ethereum with ADMIN_PRIVATE_KEY.
contract StartRoleBasedRecovery is RoleBasedKernelBase {
    function run() external {
        address admin = IRoleBasedValidator(VALIDATOR).getUserAdmin(ACCOUNT);
        uint256 key = _privateKey("ADMIN_PRIVATE_KEY", admin);
        bytes memory rotate = abi.encodeCall(IRoleBasedValidator.rotateCosignerWithAdmin, (admin));
        _sendRoleBased(key, _singleCall(VALIDATOR, 0, rotate));
    }
}

/// @notice After the 24-hour wait, sweeps 0x0A6a...'s assets to DCC3 in one batch: ERC-20s, then ERC-721s,
///         then native ETH.
contract SweepRoleBasedKernel is RoleBasedKernelBase {
    function run() external {
        address admin = IRoleBasedValidator(VALIDATOR).getUserAdmin(ACCOUNT);
        uint256 key = _privateKey("ADMIN_PRIVATE_KEY", admin);
        _rejectERC1155s();
        uint256 until = IRoleBasedValidator(VALIDATOR).getRotatingCosignerUntil(ACCOUNT);
        require(
            IRoleBasedValidator(VALIDATOR).getCosigner(ACCOUNT) == admin || (until != 0 && block.timestamp > until),
            "24-hour wait not finished"
        );
        Execution[] memory calls = _calls();
        if (calls.length == 0) revert NothingToSweep();
        _sendRoleBased(key, _batchCall(calls));
    }

    function _knownToken() private view returns (address) {
        if (block.chainid == 42161) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        if (block.chainid == 8453) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
        if (block.chainid == 1) return 0xb31561F0e2aaC72406103b1926356D756F07A481; // VOOI
        revert UnsupportedChain(block.chainid);
    }

    function _calls() private view returns (Execution[] memory) {
        address[] memory extra = _extraERC20s();
        address[] memory tokens = new address[](1 + extra.length);
        tokens[0] = _knownToken();
        for (uint256 i; i < extra.length; ++i) {
            tokens[i + 1] = extra[i];
        }
        return _orderedCalls(ACCOUNT, tokens);
    }
}

/// @notice Starts the 72-hour slow withdrawal for 0xA441... on Arbitrum.
contract StartBleapSlowWithdrawal is ProviderFreeKernelRecoveryBase {
    address constant ACCOUNT = 0xA4412B36BB6D1811cCA33DE395371E2Ddd558a87;
    address constant MODULE = 0x5B424D5133fAE2cE64ce739cec0796343E957131;
    bytes32 constant ID = bytes32(bytes4(0x78efa942));

    function run() external {
        if (block.chainid != 42161) revert UnsupportedChain(block.chainid);
        uint256 key = _privateKey("OWNER_PRIVATE_KEY", ICosigningModuleV2(MODULE).signers(ACCOUNT, ID));
        vm.startBroadcast(key);
        ICosigningModuleV2(MODULE).triggerSlowWithdraw(ID, ACCOUNT);
        vm.stopBroadcast();
    }
}

/// @notice After the 72-hour wait, sweeps 0xA441...'s assets to DCC3 using one SINGLE-call UserOp per asset.
contract SweepBleapKernel is ProviderFreeKernelRecoveryBase {
    address constant ACCOUNT = 0xA4412B36BB6D1811cCA33DE395371E2Ddd558a87;
    address constant MODULE = 0x5B424D5133fAE2cE64ce739cec0796343E957131;
    bytes32 constant ID = bytes32(bytes4(0x78efa942));
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    function run() external {
        if (block.chainid != 42161) revert UnsupportedChain(block.chainid);
        uint256 key = _privateKey("OWNER_PRIVATE_KEY", ICosigningModuleV2(MODULE).signers(ACCOUNT, ID));
        _rejectERC1155s();
        require(ICosigningModuleV2(MODULE).remainingSlowWithdrawTime(ACCOUNT) == 0, "72-hour wait not finished");

        Execution[] memory calls = _calls();
        if (calls.length == 0) revert NothingToSweep();
        PackedUserOperation[] memory ops = new PackedUserOperation[](calls.length);
        uint256 nonce = IEntryPointV07(ENTRY_POINT).getNonce(ACCOUNT, 0);
        for (uint256 i; i < calls.length; ++i) {
            ops[i] = _op(ACCOUNT, nonce + i, _singleCall(calls[i].target, calls[i].value, calls[i].callData));
            bytes32 hash = IEntryPointV07(ENTRY_POINT).getUserOpHash(ops[i]);
            ops[i].signature = abi.encodePacked(bytes1(0xff), _sig(key, _ethSigned(hash)));
        }
        _send(ops, key);
    }

    function _calls() private view returns (Execution[] memory) {
        address[] memory extra = _extraERC20s();
        address[] memory tokens = new address[](2 + extra.length);
        tokens[0] = USDT;
        tokens[1] = USDC;
        for (uint256 i; i < extra.length; ++i) {
            tokens[i + 2] = extra[i];
        }
        return _orderedCalls(ACCOUNT, tokens);
    }

    function _ethSigned(bytes32 hash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
