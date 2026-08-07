// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CoinbaseBlock} from "./CoinbaseBlock.sol";
import {Test} from "forge-std/Test.sol";

contract CoinbaseBlockTest is Test {
    CoinbaseBlock internal helper;

    function setUp() public {
        helper = new CoinbaseBlock();
    }

    function test_FeeRecipientTracksBlockCoinbase() public {
        address expected = address(0xBEEF);
        vm.coinbase(expected);

        assertEq(helper.feeRecipient(), expected);
        assertTrue(helper.isFeeRecipient(expected));
        assertFalse(helper.isFeeRecipient(address(0xCAFE)));
    }

    function test_BlockContext() public {
        address expected = address(0xBEEF);
        vm.coinbase(expected);
        vm.roll(123456);
        vm.warp(1_800_000_000);
        vm.fee(42 gwei);

        (
            address feeRecipient_,
            uint256 blockNumber_,
            uint256 chainId_,
            uint256 timestamp_,
            uint256 baseFee_
        ) = helper.blockContext();

        assertEq(feeRecipient_, expected);
        assertEq(blockNumber_, 123456);
        assertEq(chainId_, block.chainid);
        assertEq(timestamp_, 1_800_000_000);
        assertEq(baseFee_, 42 gwei);
    }
}
