// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CoinbaseBlock
/// @notice Read-only helper for the EVM block fee recipient (`block.coinbase`).
/// @dev This has no relationship to Coinbase, Inc. or Coinbase Smart Wallet.
contract CoinbaseBlock {
    /// @notice Returns the current block fee recipient / proposer beneficiary.
    function feeRecipient() external view returns (address) {
        return block.coinbase;
    }

    /// @notice Returns whether `account` is the current block fee recipient.
    function isFeeRecipient(address account) external view returns (bool) {
        return account == block.coinbase;
    }

    /// @notice Snapshot useful for Foundry tests and off-chain diagnostics.
    function blockContext()
        external
        view
        returns (
            address feeRecipient_,
            uint256 blockNumber_,
            uint256 chainId_,
            uint256 timestamp_,
            uint256 baseFee_
        )
    {
        return (
            block.coinbase,
            block.number,
            block.chainid,
            block.timestamp,
            block.basefee
        );
    }
}
