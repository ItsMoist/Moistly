// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DCC3Sweeper} from "../contracts/sweep/DCC3Sweeper.sol";

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
}

contract MockNFT is ERC721("Mock", "M") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

contract MockMulti is ERC1155("") {
    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

contract AcceptAll {
    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}

/// @notice Arbitrum fork tests: a real Kernel v3.1 account delegatecalls DCC3Sweeper.
/// @dev Set KERNEL_FORK_RPC_URL to an Arbitrum RPC to run; skipped otherwise.
contract DCC3SweeperForkTest is Test {
    address constant KERNEL_V3_1_FACTORY = 0xaac5D4240AF87249B3f71BC8E4A2cae074A3E419;
    address constant ECDSA_VALIDATOR = 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;
    bytes32 constant MODE_DELEGATECALL = bytes32(uint256(0xFF) << 248);

    DCC3Sweeper sweeper;
    IKernel kernel;
    MockNFT nft;
    MockMulti multi;

    function setUp() public {
        string memory rpc = vm.envOr("KERNEL_FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        require(block.chainid == 42161, "DCC3Sweeper tests need an Arbitrum RPC");

        sweeper = new DCC3Sweeper();
        nft = new MockNFT();
        multi = new MockMulti();

        bytes21 rootValidator = bytes21(abi.encodePacked(bytes1(0x01), ECDSA_VALIDATOR));
        bytes memory init = abi.encodeCall(
            IKernel.initialize,
            (rootValidator, address(0), abi.encodePacked(makeAddr("owner")), bytes(""), new bytes[](0))
        );
        kernel = IKernel(IKernelFactory(KERNEL_V3_1_FACTORY).createAccount(init, bytes32(0)));

        deal(USDC, address(kernel), 1_000e6);
        deal(WETH, address(kernel), 2 ether);
        nft.mint(address(kernel), 1);
        nft.mint(address(kernel), 2);
        vm.deal(address(kernel), 3 ether);
    }

    function _sweep(DCC3Sweeper.TokenId[] memory erc1155s) internal {
        address[] memory erc20s = new address[](2);
        erc20s[0] = USDC;
        erc20s[1] = WETH;
        DCC3Sweeper.TokenId[] memory erc721s = new DCC3Sweeper.TokenId[](2);
        erc721s[0] = DCC3Sweeper.TokenId(address(nft), 1);
        erc721s[1] = DCC3Sweeper.TokenId(address(nft), 2);

        bytes memory data = abi.encodeCall(DCC3Sweeper.sweep, (erc20s, erc721s, erc1155s));
        vm.prank(address(kernel));
        kernel.execute(MODE_DELEGATECALL, abi.encodePacked(address(sweeper), data));
    }

    /// @dev Ranks the account's Swept* events: 0 = ERC20, 1 = ERC721, 2 = ERC1155, 3 = native.
    function _assertOrder(uint256 expectedCount) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 last;
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(kernel)) continue;
            bytes32 t = logs[i].topics[0];
            uint256 rank;
            if (t == DCC3Sweeper.SweptERC20.selector) rank = 0;
            else if (t == DCC3Sweeper.SweptERC721.selector) rank = 1;
            else if (t == DCC3Sweeper.SweptERC1155.selector) rank = 2;
            else if (t == DCC3Sweeper.SweptNative.selector) rank = 3;
            else continue;
            assertGe(rank, last, "asset swept out of order");
            last = rank;
            ++count;
        }
        assertEq(count, expectedCount);
        assertEq(last, 3, "ETH must be swept last");
    }

    function test_sweep_toRealDCC3() public {
        uint256 dccEth = DCC3.balance;
        uint256 dccUsdc = IERC20(USDC).balanceOf(DCC3);
        uint256 dccWeth = IERC20(WETH).balanceOf(DCC3);

        vm.recordLogs();
        _sweep(new DCC3Sweeper.TokenId[](0));
        _assertOrder(5);

        assertEq(IERC20(USDC).balanceOf(DCC3) - dccUsdc, 1_000e6);
        assertEq(IERC20(WETH).balanceOf(DCC3) - dccWeth, 2 ether);
        assertEq(nft.ownerOf(1), DCC3);
        assertEq(nft.ownerOf(2), DCC3);
        assertEq(DCC3.balance - dccEth, 3 ether);
        assertEq(IERC20(USDC).balanceOf(address(kernel)), 0);
        assertEq(IERC20(WETH).balanceOf(address(kernel)), 0);
        assertEq(address(kernel).balance, 0);
    }

    /// @dev DCC3's current 7702 delegate has no onERC1155Received, so ERC-1155 transfers to it revert.
    function test_sweep_erc1155_rejectedByRealDCC3() public {
        multi.mint(address(kernel), 7, 5);
        DCC3Sweeper.TokenId[] memory erc1155s = new DCC3Sweeper.TokenId[](1);
        erc1155s[0] = DCC3Sweeper.TokenId(address(multi), 7);
        vm.expectRevert("Delegatecall failed");
        _sweep(erc1155s);
    }

    function test_sweep_fullOrder_withErc1155Receiver() public {
        vm.etch(DCC3, address(new AcceptAll()).code);
        multi.mint(address(kernel), 7, 5);
        DCC3Sweeper.TokenId[] memory erc1155s = new DCC3Sweeper.TokenId[](1);
        erc1155s[0] = DCC3Sweeper.TokenId(address(multi), 7);

        vm.recordLogs();
        _sweep(erc1155s);
        _assertOrder(6);
        assertEq(multi.balanceOf(DCC3, 7), 5);
        assertEq(address(kernel).balance, 0);
    }

    function test_sweep_directCall_reverts() public {
        vm.expectRevert(DCC3Sweeper.NotDelegateCall.selector);
        sweeper.sweep(new address[](0), new DCC3Sweeper.TokenId[](0), new DCC3Sweeper.TokenId[](0));
    }
}
