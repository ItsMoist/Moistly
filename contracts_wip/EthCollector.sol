// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "/lib/forge-std/src/console.sol";
/**
 * @title EthCollector
 * @dev Contract to collect ETH from multiple accounts and send to a designated recipient
 *      Useful for testing on local Ganache networks
 */
contract EthCollector {
    address public owner;
    address public recipient;
    bool public locked;

    event EthReceived(address indexed from, uint256 amount);
    event EthCollected(uint256 totalAmount);
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier notLocked() {
        require(!locked, "Contract is locked");
        _;
    }

    /**
     * @dev Constructor sets the owner and recipient
     * @param _recipient The address that will receive all collected ETH
     */
    constructor(address _recipient) {
        require(_recipient != address(0), "Recipient cannot be zero address");
        owner = msg.sender;
        recipient = _recipient;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Receive function to accept ETH transfers
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @dev Fallback function to accept ETH transfers
     */
    fallback() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @dev Collect all ETH from the contract and send to recipient
     *      Only callable by owner
     */
    function collectEth() external onlyOwner notLocked {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to collect");
        
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "ETH transfer failed");
        
        emit EthCollected(balance);
    }

    /**
     * @dev Update the recipient address
     *      Only callable by owner
     * @param _newRecipient The new recipient address
     */
    function updateRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Recipient cannot be zero address");
        require(_newRecipient != recipient, "New recipient is the same as current");
        
        address oldRecipient = recipient;
        recipient = _newRecipient;
        emit RecipientUpdated(oldRecipient, _newRecipient);
    }

    /**
     * @dev Transfer ownership to a new address
     *      Only callable by owner
     * @param _newOwner The new owner address
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be zero address");
        require(_newOwner != owner, "New owner is the same as current");
        
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    /**
     * @dev Lock the contract to prevent further collections
     *      Only callable by owner
     */
    function lockContract() external onlyOwner {
        locked = true;
    }

    /**
     * @dev Get contract balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get contract info
     */
    function getContractInfo() external view returns (
        address _owner,
        address _recipient,
        uint256 _balance,
        bool _locked
    ) {
        return (owner, recipient, address(this).balance, locked);
    }
}
