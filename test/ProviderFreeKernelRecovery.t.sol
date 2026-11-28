// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    StartRoleBasedRecovery,
    SweepRoleBasedKernel,
    StartBleapSlowWithdrawal,
    SweepBleapKernel,
    IRoleBasedValidator,
    ICosigningModuleV2
} from "../script/ProviderFreeKernelRecovery.s.sol";

/// @notice Fork tests for the provider-free recovery scripts against the real accounts and modules.
/// @dev The real signer keys are unavailable, so each test points the account's on-chain signer at a test key
///      via vm.store, then runs the scripts unchanged. Set RECOVERY_FORK_TESTS=1 to run (uses public RPCs, or
///      ARB_RPC_URL / BASE_RPC_URL / ETH_RPC_URL).
contract ProviderFreeKernelRecoveryForkTest is Test {
    address constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;
    address constant K1 = 0x0A6aa42783756Dd3755a80df8F641Aa4F16C7F2C;
    address constant K2 = 0xA4412B36BB6D1811cCA33DE395371E2Ddd558a87;
    address constant ROLE_VALIDATOR = 0xA24bD06230f3F54e5bf266AE7A41750eE3b789FA;
    address constant BLEAP_MODULE = 0x5B424D5133fAE2cE64ce739cec0796343E957131;
    bytes32 constant BLEAP_ID = bytes32(bytes4(0x78efa942));
    address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARB_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant VOOI = 0xb31561F0e2aaC72406103b1926356D756F07A481;

    uint256 constant KEY = 0xA11CE;
    address signer;

    function setUp() public {
        if (!vm.envOr("RECOVERY_FORK_TESTS", false)) vm.skip(true);
        signer = vm.addr(KEY);
        vm.setEnv("ADMIN_PRIVATE_KEY", vm.toString(KEY));
        vm.setEnv("OWNER_PRIVATE_KEY", vm.toString(KEY));
    }

    function _fork(string memory envName, string memory fallbackUrl) internal {
        vm.createSelectFork(vm.envOr(envName, fallbackUrl));
        vm.deal(signer, 1 ether);
    }

    /// @dev validatorStorage is mapping slot 0: userAdmin at +0, sessionKeyExists mapping at +6.
    function _useTestRoleBasedAdmin() internal {
        uint256 base = uint256(keccak256(abi.encode(K1, uint256(0))));
        vm.store(ROLE_VALIDATOR, bytes32(base), bytes32(uint256(uint160(signer))));
        vm.store(ROLE_VALIDATOR, keccak256(abi.encode(signer, base + 6)), bytes32(uint256(1)));
        assertEq(IRoleBasedValidator(ROLE_VALIDATOR).getUserAdmin(K1), signer);
    }

    function _roleBasedFlow(address token) internal {
        _useTestRoleBasedAdmin();
        address providerCosigner = IRoleBasedValidator(ROLE_VALIDATOR).getCosigner(K1);
        assertTrue(providerCosigner != signer);

        new StartRoleBasedRecovery().run();
        uint256 until = IRoleBasedValidator(ROLE_VALIDATOR).getRotatingCosignerUntil(K1);
        assertEq(until, block.timestamp + 24 hours);

        SweepRoleBasedKernel sweep = new SweepRoleBasedKernel();
        vm.expectRevert("24-hour wait not finished");
        sweep.run();

        vm.warp(until + 1);
        uint256 tokenBalance = IERC20(token).balanceOf(K1);
        uint256 nativeBalance = K1.balance;
        uint256 dccToken = IERC20(token).balanceOf(DCC3);
        uint256 dccNative = DCC3.balance;
        assertGt(tokenBalance, 0);

        sweep.run();

        assertEq(IRoleBasedValidator(ROLE_VALIDATOR).getCosigner(K1), signer);
        assertEq(IERC20(token).balanceOf(K1), 0);
        assertEq(K1.balance, 0);
        assertEq(IERC20(token).balanceOf(DCC3) - dccToken, tokenBalance);
        assertEq(DCC3.balance - dccNative, nativeBalance);
    }

    function test_roleBased_arbitrum() public {
        _fork("ARB_RPC_URL", "https://arbitrum-one-rpc.publicnode.com");
        assertGt(K1.balance, 0);
        _roleBasedFlow(ARB_USDC);
    }

    function test_roleBased_base() public {
        _fork("BASE_RPC_URL", "https://base-rpc.publicnode.com");
        _roleBasedFlow(BASE_USDC);
    }

    function test_roleBased_ethereum() public {
        _fork("ETH_RPC_URL", "https://ethereum-rpc.publicnode.com");
        _roleBasedFlow(VOOI);
    }

    function test_bleap_arbitrum() public {
        _fork("ARB_RPC_URL", "https://arbitrum-one-rpc.publicnode.com");
        // signers is mapping slot 6: signers[wallet][id].
        bytes32 slot = keccak256(abi.encode(BLEAP_ID, keccak256(abi.encode(K2, uint256(6)))));
        vm.store(BLEAP_MODULE, slot, bytes32(uint256(uint160(signer))));
        assertEq(ICosigningModuleV2(BLEAP_MODULE).signers(K2, BLEAP_ID), signer);
        vm.deal(K2, 0.01 ether);

        new StartBleapSlowWithdrawal().run();
        assertEq(ICosigningModuleV2(BLEAP_MODULE).remainingSlowWithdrawTime(K2), 72 hours);

        SweepBleapKernel sweep = new SweepBleapKernel();
        vm.expectRevert("72-hour wait not finished");
        sweep.run();

        vm.warp(block.timestamp + 72 hours);
        uint256 usdt = IERC20(ARB_USDT).balanceOf(K2);
        uint256 usdc = IERC20(ARB_USDC).balanceOf(K2);
        uint256 dccUsdt = IERC20(ARB_USDT).balanceOf(DCC3);
        uint256 dccUsdc = IERC20(ARB_USDC).balanceOf(DCC3);
        uint256 dccNative = DCC3.balance;
        assertGt(usdt, 0);
        assertGt(usdc, 0);

        sweep.run();

        assertEq(IERC20(ARB_USDT).balanceOf(K2), 0);
        assertEq(IERC20(ARB_USDC).balanceOf(K2), 0);
        assertEq(K2.balance, 0);
        assertEq(IERC20(ARB_USDT).balanceOf(DCC3) - dccUsdt, usdt);
        assertEq(IERC20(ARB_USDC).balanceOf(DCC3) - dccUsdc, usdc);
        assertEq(DCC3.balance - dccNative, 0.01 ether);
    }
}
