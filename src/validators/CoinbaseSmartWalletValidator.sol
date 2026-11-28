// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICoinbaseSignatureWallet {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

/// @notice ERC-1271 adapter for one trusted, already deployed Coinbase Smart Wallet.
/// @dev Supply the original application digest and the wallet's encoded SignatureWrapper.
/// The wallet applies its replay-safe domain and verifies the selected owner.
contract CoinbaseSmartWalletValidator {
    ICoinbaseSignatureWallet public immutable wallet;

    error WalletHasNoCode();
    error InvalidWalletSignature();

    constructor(address wallet_) {
        if (wallet_.code.length == 0) revert WalletHasNoCode();
        wallet = ICoinbaseSignatureWallet(wallet_);
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        bytes4 result = wallet.isValidSignature(hash, signature);
        if (result != ICoinbaseSignatureWallet.isValidSignature.selector) revert InvalidWalletSignature();
        return result;
    }
}
