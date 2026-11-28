// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @notice Moves an account's assets to DCC3 in a fixed order: ERC-20 -> ERC-721 -> ERC-1155 -> native ETH.
/// @dev Must be DELEGATECALLed by the account (e.g. Kernel `execute` with CALLTYPE_DELEGATECALL), so
///      `address(this)` is the account. Native ETH is swept last using the balance at execution time.
///      ERC-721s use `transferFrom` because DCC3's 7702 delegate does not implement `onERC721Received`.
contract DCC3Sweeper {
    using SafeERC20 for IERC20;

    address public constant DCC3 = 0x75e732608Bc17B23D01f01728562Ee844196DCC3;

    struct TokenId {
        address token;
        uint256 id;
    }

    address private immutable _self = address(this);

    error NotDelegateCall();
    error NativeTransferFailed();

    event SweptERC20(address indexed token, uint256 amount);
    event SweptERC721(address indexed token, uint256 indexed id);
    event SweptERC1155(address indexed token, uint256 indexed id, uint256 amount);
    event SweptNative(uint256 amount);

    function sweep(address[] calldata erc20s, TokenId[] calldata erc721s, TokenId[] calldata erc1155s) external {
        if (address(this) == _self) revert NotDelegateCall();

        for (uint256 i; i < erc20s.length; ++i) {
            uint256 amount = IERC20(erc20s[i]).balanceOf(address(this));
            if (amount != 0) {
                IERC20(erc20s[i]).safeTransfer(DCC3, amount);
                emit SweptERC20(erc20s[i], amount);
            }
        }

        for (uint256 i; i < erc721s.length; ++i) {
            IERC721(erc721s[i].token).transferFrom(address(this), DCC3, erc721s[i].id);
            emit SweptERC721(erc721s[i].token, erc721s[i].id);
        }

        for (uint256 i; i < erc1155s.length; ++i) {
            uint256 amount = IERC1155(erc1155s[i].token).balanceOf(address(this), erc1155s[i].id);
            if (amount != 0) {
                IERC1155(erc1155s[i].token).safeTransferFrom(address(this), DCC3, erc1155s[i].id, amount, "");
                emit SweptERC1155(erc1155s[i].token, erc1155s[i].id, amount);
            }
        }

        uint256 native = address(this).balance;
        if (native != 0) {
            (bool ok,) = DCC3.call{value: native}("");
            if (!ok) revert NativeTransferFailed();
            emit SweptNative(native);
        }
    }
}
