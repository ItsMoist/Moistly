// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MoistExecutor} from "../contracts/MoistExecutor.sol";
import {MoistKernelExecutorAdapter} from "../contracts/MoistKernelExecutorAdapter.sol";

interface IKernelFactory {
    function createAccount(bytes calldata data, bytes32 salt) external payable returns (address);
}

interface IKernel {
    function initialize(
        bytes21 rootValidator,
        address hook,
        bytes calldata validatorData,
        bytes calldata hookData,
        bytes[] calldata initConfig
    ) external;
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable;
    function installModule(uint256 moduleType, address module, bytes calldata initData) external payable;
    function uninstallModule(uint256 moduleType, address module, bytes calldata deInitData) external payable;
    function isModuleInstalled(uint256 moduleType, address module, bytes calldata ctx) external view returns (bool);
    function accountId() external view returns (string memory);
}

contract Sink {
    uint256 public hits;

    function ping(uint256 x) external payable returns (uint256) {
        hits += x;
        return x * 2;
    }
}

contract Reverter {
    function boom() external pure {
        revert("boom");
    }
}

/// @notice Mainnet-fork tests against the deployed Kernel v3.1 implementation and factory.
/// @dev Set MAINNET_RPC_URL to run; skipped otherwise.
contract MoistKernelExecutorAdapterForkTest is Test {
    address constant KERNEL_V3_1_FACTORY = 0xaac5D4240AF87249B3f71BC8E4A2cae074A3E419;
    address constant ECDSA_VALIDATOR = 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address attacker = makeAddr("attacker");
    MoistExecutor executor;
    MoistKernelExecutorAdapter adapter;
    IKernel kernel;
    Sink sink;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        executor = MoistExecutor(
            payable(address(
                    new ERC1967Proxy(address(new MoistExecutor()), abi.encodeCall(MoistExecutor.initialize, (owner)))
                ))
        );
        vm.prank(owner);
        executor.setOperator(operator, true);
        adapter = new MoistKernelExecutorAdapter();
        sink = new Sink();

        kernel = _createKernel(abi.encode(address(executor)), 1);
        vm.deal(address(kernel), 10 ether);
    }

    function _installData(bytes memory executorData) internal pure returns (bytes memory) {
        return abi.encodePacked(address(0), abi.encode(executorData, bytes("")));
    }

    function _createKernel(bytes memory executorData, uint256 salt) internal returns (IKernel) {
        bytes[] memory initConfig = new bytes[](1);
        initConfig[0] = abi.encodeCall(IKernel.installModule, (2, address(adapter), _installData(executorData)));
        bytes21 rootValidator = bytes21(abi.encodePacked(bytes1(0x01), ECDSA_VALIDATOR));
        bytes memory init = abi.encodeCall(
            IKernel.initialize, (rootValidator, address(0), abi.encodePacked(owner), bytes(""), initConfig)
        );
        return IKernel(IKernelFactory(KERNEL_V3_1_FACTORY).createAccount(init, bytes32(salt)));
    }

    function _single(IKernel account, address target, uint256 value, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(MoistKernelExecutorAdapter.executeSingle, (address(account), target, value, data));
    }

    /// @dev Simulates the account calling a contract via its own execute (e.g. from a root-validated userOp).
    function _accountCall(IKernel account, address target, bytes memory data) internal {
        vm.prank(address(account));
        account.execute(bytes32(0), abi.encodePacked(target, uint256(0), data));
    }

    function test_installed() public view {
        assertEq(kernel.accountId(), "kernel.advanced.v0.3.1");
        assertTrue(kernel.isModuleInstalled(2, address(adapter), ""));
        assertEq(adapter.trustedExecutor(address(kernel)), address(executor));
        assertFalse(adapter.targetRestricted(address(kernel)));
    }

    function test_executeSingle_ownerAndOperator() public {
        bytes memory inner = _single(kernel, address(sink), 1 ether, abi.encodeCall(Sink.ping, (7)));
        vm.prank(owner);
        bytes[] memory results = abi.decode(executor.execute(address(adapter), 0, inner), (bytes[]));
        assertEq(abi.decode(results[0], (uint256)), 14);

        vm.prank(operator);
        executor.execute(address(adapter), 0, inner);

        assertEq(sink.hits(), 14);
        assertEq(address(sink).balance, 2 ether);
        assertEq(address(kernel).balance, 8 ether);
    }

    function test_executeBatch() public {
        MoistKernelExecutorAdapter.Execution[] memory calls = new MoistKernelExecutorAdapter.Execution[](2);
        calls[0] = MoistKernelExecutorAdapter.Execution(address(sink), 0.5 ether, abi.encodeCall(Sink.ping, (1)));
        calls[1] = MoistKernelExecutorAdapter.Execution(address(sink), 0, abi.encodeCall(Sink.ping, (2)));

        vm.prank(owner);
        executor.execute(
            address(adapter), 0, abi.encodeCall(MoistKernelExecutorAdapter.executeBatch, (address(kernel), calls))
        );

        assertEq(sink.hits(), 3);
        assertEq(address(sink).balance, 0.5 ether);
    }

    function test_executeBatch_isAtomic() public {
        Reverter reverter = new Reverter();
        MoistKernelExecutorAdapter.Execution[] memory calls = new MoistKernelExecutorAdapter.Execution[](2);
        calls[0] = MoistKernelExecutorAdapter.Execution(address(sink), 1 ether, abi.encodeCall(Sink.ping, (1)));
        calls[1] = MoistKernelExecutorAdapter.Execution(address(reverter), 0, abi.encodeCall(Reverter.boom, ()));

        vm.prank(owner);
        vm.expectRevert();
        executor.execute(
            address(adapter), 0, abi.encodeCall(MoistKernelExecutorAdapter.executeBatch, (address(kernel), calls))
        );

        assertEq(sink.hits(), 0);
        assertEq(address(kernel).balance, 10 ether);
    }

    function test_directCaller_rejected() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MoistKernelExecutorAdapter.UnauthorizedCaller.selector, attacker));
        adapter.executeSingle(address(kernel), attacker, 1 ether, "");
    }

    function test_nonOperator_rejectedByExecutor() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MoistExecutor.Unauthorized.selector, attacker));
        executor.execute(address(adapter), 0, _single(kernel, attacker, 1 ether, ""));
    }

    function test_selfCall_forbidden() public {
        bytes memory takeover = abi.encodeCall(IKernel.uninstallModule, (2, address(adapter), bytes("")));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                MoistExecutor.CallFailed.selector,
                0,
                address(adapter),
                abi.encodeWithSelector(MoistKernelExecutorAdapter.SelfCallForbidden.selector)
            )
        );
        executor.execute(address(adapter), 0, _single(kernel, address(kernel), 0, takeover));

        MoistKernelExecutorAdapter.Execution[] memory calls = new MoistKernelExecutorAdapter.Execution[](1);
        calls[0] = MoistKernelExecutorAdapter.Execution(address(kernel), 0, takeover);
        vm.prank(owner);
        vm.expectRevert();
        executor.execute(
            address(adapter), 0, abi.encodeCall(MoistKernelExecutorAdapter.executeBatch, (address(kernel), calls))
        );
        assertTrue(kernel.isModuleInstalled(2, address(adapter), ""));
    }

    function test_allowlistFromInstallData() public {
        address[] memory targets = new address[](1);
        targets[0] = address(sink);
        IKernel restricted = _createKernel(abi.encode(address(executor), targets), 2);
        vm.deal(address(restricted), 1 ether);

        assertTrue(adapter.targetRestricted(address(restricted)));
        assertTrue(adapter.isTargetAllowed(address(restricted), address(sink)));

        vm.prank(owner);
        executor.execute(
            address(adapter), 0, _single(restricted, address(sink), 0.1 ether, abi.encodeCall(Sink.ping, (1)))
        );
        assertEq(sink.hits(), 1);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                MoistExecutor.CallFailed.selector,
                0,
                address(adapter),
                abi.encodeWithSelector(MoistKernelExecutorAdapter.TargetNotAllowed.selector, attacker)
            )
        );
        executor.execute(address(adapter), 0, _single(restricted, attacker, 0.1 ether, ""));
    }

    function test_accountManagesAllowlist() public {
        _accountCall(kernel, address(adapter), abi.encodeCall(MoistKernelExecutorAdapter.setTargetRestricted, (true)));
        assertTrue(adapter.targetRestricted(address(kernel)));

        vm.prank(owner);
        vm.expectRevert();
        executor.execute(address(adapter), 0, _single(kernel, address(sink), 0, abi.encodeCall(Sink.ping, (1))));

        _accountCall(
            kernel, address(adapter), abi.encodeCall(MoistKernelExecutorAdapter.setTargetAllowed, (address(sink), true))
        );
        vm.prank(owner);
        executor.execute(address(adapter), 0, _single(kernel, address(sink), 0, abi.encodeCall(Sink.ping, (1))));
        assertEq(sink.hits(), 1);
    }

    function test_allowlistSetters_requireInstall() public {
        vm.prank(attacker);
        vm.expectRevert(MoistKernelExecutorAdapter.NotInstalled.selector);
        adapter.setTargetRestricted(false);

        vm.prank(attacker);
        vm.expectRevert(MoistKernelExecutorAdapter.NotInstalled.selector);
        adapter.setTargetAllowed(attacker, true);
    }

    function test_uninstall_blocksExecution_andResetsAllowlist() public {
        _accountCall(
            kernel, address(adapter), abi.encodeCall(MoistKernelExecutorAdapter.setTargetAllowed, (address(sink), true))
        );
        _accountCall(kernel, address(adapter), abi.encodeCall(MoistKernelExecutorAdapter.setTargetRestricted, (true)));

        vm.prank(address(kernel));
        kernel.uninstallModule(2, address(adapter), "");
        assertFalse(kernel.isModuleInstalled(2, address(adapter), ""));
        assertEq(adapter.trustedExecutor(address(kernel)), address(0));
        assertFalse(adapter.targetRestricted(address(kernel)));

        vm.prank(owner);
        vm.expectRevert();
        executor.execute(address(adapter), 0, _single(kernel, address(sink), 0, ""));

        vm.prank(address(kernel));
        kernel.installModule(2, address(adapter), _installData(abi.encode(address(executor))));
        assertEq(adapter.trustedExecutor(address(kernel)), address(executor));
        assertFalse(adapter.isTargetAllowed(address(kernel), address(sink)));
    }

    function test_plainAbiEncodeInitData_reverts() public {
        MoistKernelExecutorAdapter other = new MoistKernelExecutorAdapter();
        vm.prank(address(kernel));
        vm.expectRevert();
        kernel.installModule(2, address(other), abi.encode(address(executor)));
    }
}
