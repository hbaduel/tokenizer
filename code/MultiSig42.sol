// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MultiSig42 {
    struct Transaction {
        address to;
        bytes data;
        bool executed;
        uint256 nbConfirmations;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public immutable nbConfirmationsRequired;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    event TransactionSubmitted(uint256 indexed transactionIndex, address indexed owner, address indexed to, bytes data);
    event TransactionConfirmed(uint256 indexed transactionIndex, address indexed owner);
    event TransactionRevoked(uint256 indexed transactionIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionIndex, address indexed owner);

    error OwnersEmpty();
    error OwnersArrayContainsZeroAddress();
    error OwnersArrayContainsDuplicateAddress(address duplicateAddress);
    error InvalidNumberOfConfirmations(uint256 min, uint256 max, uint256 provided);
    error TransactionDoesNotExist(uint256 transactionIndex);
    error NotAnOwner(address account);
    error TransactionToZeroAddress();
    error TransactionToNonContractAddress(address to);
    error TransactionAlreadyExecuted(uint256 transactionIndex);
    error TransactionAlreadyConfirmed(uint256 transactionIndex, address owner);
    error TransactionNotConfirmed(uint256 transactionIndex, address owner);
    error NotEnoughConfirmations(uint256 transactionIndex, uint256 confirmations, uint256 required);
    error TransactionExecutionFailed(uint256 transactionIndex, bytes returnData);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotAnOwner(msg.sender);
        }
        _;
    }

    modifier transactionExists(uint256 transactionIndex) {
        if (transactionIndex >= transactions.length) {
            revert TransactionDoesNotExist(transactionIndex);
        }
        _;
    }

    constructor(address[] memory _owners, uint256 _nbConfirmationsRequired) {
        if (_owners.length == 0) {
            revert OwnersEmpty();
        }
        if (_nbConfirmationsRequired == 0 || _nbConfirmationsRequired > _owners.length) {
            revert InvalidNumberOfConfirmations(1, _owners.length, _nbConfirmationsRequired);
        }
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) {
                revert OwnersArrayContainsZeroAddress();
            }
            if (isOwner[owner]) {
                revert OwnersArrayContainsDuplicateAddress(owner);
            }
            isOwner[owner] = true;
        }
        owners = _owners;
        nbConfirmationsRequired = _nbConfirmationsRequired;
    }

    function submitTransaction(address to, bytes calldata data) external onlyOwner returns (uint256) {
        if (to == address(0)) {
            revert TransactionToZeroAddress();
        } else if (to.code.length == 0) {
            revert TransactionToNonContractAddress(to);
        }
        transactions.push(Transaction({to: to, data: data, executed: false, nbConfirmations: 0}));
        uint256 transactionIndex = transactions.length - 1;
        emit TransactionSubmitted(transactionIndex, msg.sender, to, data);
        return transactionIndex;
    }

    function confirmTransaction(uint256 transactionIndex) external onlyOwner transactionExists(transactionIndex) {
        Transaction storage transaction = transactions[transactionIndex];
        if (transaction.executed) {
            revert TransactionAlreadyExecuted(transactionIndex);
        } else if (isConfirmed[transactionIndex][msg.sender]) {
            revert TransactionAlreadyConfirmed(transactionIndex, msg.sender);
        }
        isConfirmed[transactionIndex][msg.sender] = true;
        transaction.nbConfirmations += 1;
        emit TransactionConfirmed(transactionIndex, msg.sender);
    }

    function revokeConfirmation(uint256 transactionIndex) external onlyOwner transactionExists(transactionIndex) {
        Transaction storage transaction = transactions[transactionIndex];
        if (transaction.executed) {
            revert TransactionAlreadyExecuted(transactionIndex);
        } else if (!isConfirmed[transactionIndex][msg.sender]) {
            revert TransactionNotConfirmed(transactionIndex, msg.sender);
        }
        isConfirmed[transactionIndex][msg.sender] = false;
        transaction.nbConfirmations -= 1;
        emit TransactionRevoked(transactionIndex, msg.sender);
    }

    function executeTransaction(uint256 transactionIndex) external onlyOwner transactionExists(transactionIndex) {
        Transaction storage transaction = transactions[transactionIndex];
        if (transaction.executed) {
            revert TransactionAlreadyExecuted(transactionIndex);
        } else if (transaction.nbConfirmations < nbConfirmationsRequired) {
            revert NotEnoughConfirmations(transactionIndex, transaction.nbConfirmations, nbConfirmationsRequired);
        }
        transaction.executed = true;
        emit TransactionExecuted(transactionIndex, msg.sender);
        (bool success, bytes memory returnData) = transaction.to.call(transaction.data);
        if (!success) {
            revert TransactionExecutionFailed(transactionIndex, returnData);
        }
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }
}
