// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DCC3Sweeper} from "../contracts/sweep/DCC3Sweeper.sol";

interface IKernelExecute {
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable;
}

/// @notice Prints the Kernel `execute` calldata (userOp callData) that delegatecalls DCC3Sweeper.
/// @dev Env: SWEEPER (deployed DCC3Sweeper), optional comma-separated ERC20S, ERC721_TOKENS + ERC721_IDS,
///      ERC1155_TOKENS + ERC1155_IDS. Sign and send the result as a userOp from the Kernel's root validator.
contract SweepToDCC3 is Script {
    bytes32 constant MODE_DELEGATECALL = bytes32(uint256(0xFF) << 248);

    function run() external view returns (bytes memory callData) {
        address sweeper = vm.envAddress("SWEEPER");
        address[] memory erc20s = vm.envOr("ERC20S", ",", new address[](0));
        DCC3Sweeper.TokenId[] memory erc721s = _pairs("ERC721_TOKENS", "ERC721_IDS");
        DCC3Sweeper.TokenId[] memory erc1155s = _pairs("ERC1155_TOKENS", "ERC1155_IDS");

        bytes memory sweepData = abi.encodeCall(DCC3Sweeper.sweep, (erc20s, erc721s, erc1155s));
        callData = abi.encodeCall(IKernelExecute.execute, (MODE_DELEGATECALL, abi.encodePacked(sweeper, sweepData)));
        console2.logBytes(callData);
    }

    function _pairs(string memory tokensVar, string memory idsVar)
        internal
        view
        returns (DCC3Sweeper.TokenId[] memory out)
    {
        address[] memory tokens = vm.envOr(tokensVar, ",", new address[](0));
        uint256[] memory ids = vm.envOr(idsVar, ",", new uint256[](0));
        require(tokens.length == ids.length, string.concat(tokensVar, " / ", idsVar, " length mismatch"));
        out = new DCC3Sweeper.TokenId[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            out[i] = DCC3Sweeper.TokenId(tokens[i], ids[i]);
        }
    }
}
