// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/counter/Counters.sol";
import "./DAOCore.sol";

/**
 * @title Treasury
 * @dev Contract for DAO treasury management
 *
 * This contract implements:
 * - Multi-signature functionality for fund management
 * - Transaction execution with approval thresholds
 * - Asset tracking and reporting
 * - Budget allocation and management
 */
contract Treasury is Initializable {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    
    // Transaction states
    enum TransactionState {
        Pending,    // Transaction is created but not executed
        Approved,   // Transaction is approved but not executed
        Executed,   // Transaction was executed
        Canceled,   // Transaction was canceled
        Failed      // Transaction execution failed
    }
    
    // Transaction structure
    struct Transaction {
        uint256 id;                     // Unique identifier
        address proposer;               // Address that created the transaction
        string description;             // Description of the transaction
        address target;                 // Target address for the transaction
        uint256 value;                  // ETH value for the transaction
        bytes data;                     // Calldata for the transaction
        bool executed;                  // Whether the transaction has been executed
        bool canceled;                  // Whether the transaction has been canceled
        uint256 approvalCount;          // Number of approvals
        mapping(address => bool) approvals; // Mapping of approvals by address
        uint256 createdAt;              // When the transaction was created
        string category;                // Transaction category for reporting
    }
    
    // Transaction summary (for external view)
    struct TransactionSummary {
        uint256 id;
        address proposer;
        string description;
        address target;
        uint256 value;
        bool executed;
        bool canceled;
        uint256 approvalCount;
        uint256 createdAt;
        string category;
        TransactionState state;
    }
    
    // Asset structure
    struct Asset {
        address tokenAddress;           // Address of the token (address(0) for ETH)
        string symbol;                  // Symbol of the token
        uint8 decimals;                 // Decimals of the token
        bool tracked;                   // Whether the asset is tracked
    }
    
    // Budget structure
    struct Budget {
        string category;                // Budget category
        uint256 allocation;             // Allocated amount
        uint256 spent;                  // Spent amount
        uint256 period;                 // Budget period (timestamp)
        bool active;                    // Whether the budget is active
    }
    
    // Contract references
    address public daoCore;
    address public governanceContract;
    
    // Treasury parameters
    uint256 public approvalThreshold;   // Number of approvals needed for execution
    
    // Transaction tracking
    Counters.Counter private _transactionIdTracker;
    mapping(uint256 => Transaction) private _transactions;
    uint256[] private _transactionIds;
    
    // Asset tracking
    address[] private _trackedAssets;
    mapping(address => Asset) private _assets;
    
    // Budget tracking
    string[] private _budgetCategories;
    mapping(string => Budget) private _budgets;
    
    // Events
    event TransactionCreated(
        uint256 indexed transactionId,
        address indexed proposer,
        address target,
        uint256 value,
        string description,
        string category
    );
    event TransactionApproved(uint256 indexed transactionId, address indexed approver);
    event TransactionExecuted(uint256 indexed transactionId);
    event TransactionCanceled(uint256 indexed transactionId);
    event TransactionFailed(uint256 indexed transactionId, string reason);
    event AssetAdded(address indexed tokenAddress, string symbol);
    event AssetRemoved(address indexed tokenAddress);
    event BudgetCreated(string category, uint256 allocation, uint256 period);
    event BudgetUpdated(string category, uint256 allocation);
    event BudgetSpent(string category, uint256 amount, uint256 remaining);
    event FundsReceived(address indexed sender, uint256 amount);
    event TreasuryParametersUpdated(uint256 approvalThreshold);
    
    /**
     * @dev Modifier to check if the caller is a member
     */
    modifier onlyMember() {
        require(DAOCore(daoCore).isMember(msg.sender), "Treasury: caller is not a member");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is an admin
     */
    modifier onlyAdmin() {
        require(DAOCore(daoCore).isAdmin(msg.sender), "Treasury: caller is not an admin");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is the governance contract
     */
    modifier onlyGovernance() {
        require(msg.sender == governanceContract, "Treasury: caller is not the governance contract");
        _;
    }
    
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
    /**
     * @dev Initializes the contract with initial values
     * @param _daoCore The address of the DAO core contract
     * @param _governanceContract The address of the governance contract
     */
    function initialize(
        address _daoCore,
        address _governanceContract
    ) external initializer {
        require(_daoCore != address(0), "Treasury: DAO core cannot be zero address");
        require(_governanceContract != address(0), "Treasury: governance contract cannot be zero address");
        
        daoCore = _daoCore;
        governanceContract = _governanceContract;
        
        // Default to 1 approval required (can be updated later)
        approvalThreshold = 1;
        
        // Start transaction IDs at 1
        _transactionIdTracker.increment();
        
        // Add ETH as a tracked asset
        _addAsset(address(0), "ETH", 18);
    }
    
    /**
     * @dev Updates the treasury parameters
     * @param _approvalThreshold The new approval threshold
     */
    function updateTreasuryParameters(uint256 _approvalThreshold) external onlyAdmin {
        require(_approvalThreshold > 0, "Treasury: approval threshold must be greater than 0");
        
        approvalThreshold = _approvalThreshold;
        
        emit TreasuryParametersUpdated(_approvalThreshold);
    }
    
    /**
     * @dev Creates a new transaction
     * @param description The description of the transaction
     * @param target The target address for the transaction
     * @param value The ETH value for the transaction
     * @param data The calldata for the transaction
     * @param category The transaction category
     * @return The ID of the newly created transaction
     */
    function createTransaction(
        string memory description,
        address target,
        uint256 value,
        bytes memory data,
        string memory category
    ) external onlyMember returns (uint256) {
        require(target != address(0), "Treasury: target cannot be zero address");
        
        uint256 transactionId = _transactionIdTracker.current();
        _transactionIdTracker.increment();
        
        Transaction storage transaction = _transactions[transactionId];
        transaction.id = transactionId;
        transaction.proposer = msg.sender;
        transaction.description = description;
        transaction.target = target;
        transaction.value = value;
        transaction.data = data;
        transaction.createdAt = block.timestamp;
        transaction.category = category;
        
        // Auto-approve by the proposer
        transaction.approvals[msg.sender] = true;
        transaction.approvalCount = 1;
        
        _transactionIds.push(transactionId);
        
        emit TransactionCreated(
            transactionId,
            msg.sender,
            target,
            value,
            description,
            category
        );
        
        emit TransactionApproved(transactionId, msg.sender);
        
        // If only one approval is needed, execute immediately
        if (approvalThreshold == 1) {
            executeTransaction(transactionId);
        }
        
        return transactionId;
    }
    
    /**
     * @dev Approves a transaction
     * @param transactionId The ID of the transaction to approve
     */
    function approveTransaction(uint256 transactionId) external onlyMember {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        Transaction storage transaction = _transactions[transactionId];
        
        require(!transaction.executed, "Treasury: transaction already executed");
        require(!transaction.canceled, "Treasury: transaction already canceled");
        require(!transaction.approvals[msg.sender], "Treasury: transaction already approved");
        
        transaction.approvals[msg.sender] = true;
        transaction.approvalCount += 1;
        
        emit TransactionApproved(transactionId, msg.sender);
        
        // Execute if threshold is reached
        if (transaction.approvalCount >= approvalThreshold) {
            executeTransaction(transactionId);
        }
    }
    
    /**
     * @dev Executes a transaction
     * @param transactionId The ID of the transaction to execute
     */
    function executeTransaction(uint256 transactionId) public {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        Transaction storage transaction = _transactions[transactionId];
        
        require(!transaction.executed, "Treasury: transaction already executed");
        require(!transaction.canceled, "Treasury: transaction already canceled");
        require(
            transaction.approvalCount >= approvalThreshold,
            "Treasury: not enough approvals"
        );
        
        transaction.executed = true;
        
        // Update budget if category is set
        if (bytes(transaction.category).length > 0 && _budgets[transaction.category].active) {
            _updateBudgetSpending(transaction.category, transaction.value);
        }
        
        // Execute the transaction
        (bool success, bytes memory returnData) = transaction.target.call{value: transaction.value}(transaction.data);
        
        if (success) {
            emit TransactionExecuted(transactionId);
        } else {
            transaction.executed = false; // Revert execution status
            
            string memory reason;
            if (returnData.length > 0) {
                // Try to extract the revert reason
                assembly {
                    reason := mload(add(returnData, 0x20))
                }
            } else {
                reason = "Transaction execution failed";
            }
            
            emit TransactionFailed(transactionId, reason);
        }
    }
    
    /**
     * @dev Cancels a transaction
     * @param transactionId The ID of the transaction to cancel
     */
    function cancelTransaction(uint256 transactionId) external {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        Transaction storage transaction = _transactions[transactionId];
        
        require(!transaction.executed, "Treasury: transaction already executed");
        require(!transaction.canceled, "Treasury: transaction already canceled");
        
        // Only proposer, admin, or governance can cancel
        require(
            transaction.proposer == msg.sender || 
            DAOCore(daoCore).isAdmin(msg.sender) || 
            msg.sender == governanceContract,
            "Treasury: not authorized to cancel"
        );
        
        transaction.canceled = true;
        
        emit TransactionCanceled(transactionId);
    }
    
    /**
     * @dev Adds a token to tracked assets
     * @param tokenAddress The address of the token
     * @param symbol The symbol of the token
     * @param decimals The decimals of the token
     */
    function addAsset(address tokenAddress, string memory symbol, uint8 decimals) external onlyAdmin {
        require(tokenAddress != address(0), "Treasury: cannot add ETH (already tracked)");
        require(!_assets[tokenAddress].tracked, "Treasury: asset already tracked");
        
        _addAsset(tokenAddress, symbol, decimals);
    }
    
    /**
     * @dev Removes a token from tracked assets
     * @param tokenAddress The address of the token
     */
    function removeAsset(address tokenAddress) external onlyAdmin {
        require(tokenAddress != address(0), "Treasury: cannot remove ETH");
        require(_assets[tokenAddress].tracked, "Treasury: asset not tracked");
        
        // Remove from tracked assets array
        for (uint256 i = 0; i < _trackedAssets.length; i++) {
            if (_trackedAssets[i] == tokenAddress) {
                _trackedAssets[i] = _trackedAssets[_trackedAssets.length - 1];
                _trackedAssets.pop();
                break;
            }
        }
        
        // Update asset tracking status
        _assets[tokenAddress].tracked = false;
        
        emit AssetRemoved(tokenAddress);
    }
    
    /**
     * @dev Creates a new budget category
     * @param category The budget category
     * @param allocation The allocated amount
     * @param period The budget period in seconds
     */
    function createBudget(string memory category, uint256 allocation, uint256 period) external onlyAdmin {
        require(bytes(category).length > 0, "Treasury: category cannot be empty");
        require(allocation > 0, "Treasury: allocation must be greater than 0");
        require(period > 0, "Treasury: period must be greater than 0");
        require(!_budgets[category].active, "Treasury: budget already exists");
        
        _budgets[category] = Budget({
            category: category,
            allocation: allocation,
            spent: 0,
            period: period,
            active: true
        });
        
        _budgetCategories.push(category);
        
        emit BudgetCreated(category, allocation, period);
    }
    
    /**
     * @dev Updates a budget allocation
     * @param category The budget category
     * @param allocation The new allocated amount
     */
    function updateBudget(string memory category, uint256 allocation) external onlyAdmin {
        require(_budgets[category].active, "Treasury: budget does not exist");
        require(allocation > 0, "Treasury: allocation must be greater than 0");
        
        _budgets[category].allocation = allocation;
        
        emit BudgetUpdated(category, allocation);
    }
    
    /**
     * @dev Deactivates a budget
     * @param category The budget category
     */
    function deactivateBudget(string memory category) external onlyAdmin {
        require(_budgets[category].active, "Treasury: budget does not exist");
        
        _budgets[category].active = false;
    }
    
    /**
     * @dev Gets the state of a transaction
     * @param transactionId The ID of the transaction
     * @return The current state of the transaction
     */
    function getTransactionState(uint256 transactionId) public view returns (TransactionState) {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        Transaction storage transaction = _transactions[transactionId];
        
        if (transaction.canceled) {
            return TransactionState.Canceled;
        }
        
        if (transaction.executed) {
            return TransactionState.Executed;
        }
        
        if (transaction.approvalCount >= approvalThreshold) {
            return TransactionState.Approved;
        }
        
        return TransactionState.Pending;
    }
    
    /**
     * @dev Gets a transaction summary
     * @param transactionId The ID of the transaction
     * @return A transaction summary struct
     */
    function getTransaction(uint256 transactionId) external view returns (TransactionSummary memory) {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        Transaction storage transaction = _transactions[transactionId];
        
        return TransactionSummary({
            id: transaction.id,
            proposer: transaction.proposer,
            description: transaction.description,
            target: transaction.target,
            value: transaction.value,
            executed: transaction.executed,
            canceled: transaction.canceled,
            approvalCount: transaction.approvalCount,
            createdAt: transaction.createdAt,
            category: transaction.category,
            state: getTransactionState(transactionId)
        });
    }
    
    /**
     * @dev Gets the transaction data
     * @param transactionId The ID of the transaction
     * @return The transaction data
     */
    function getTransactionData(uint256 transactionId) external view returns (bytes memory) {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        return _transactions[transactionId].data;
    }
    
    /**
     * @dev Checks if an address has approved a transaction
     * @param transactionId The ID of the transaction
     * @param approver The address to check
     * @return True if the address has approved the transaction, false otherwise
     */
    function hasApproved(uint256 transactionId, address approver) external view returns (bool) {
        require(_transactionExists(transactionId), "Treasury: transaction does not exist");
        
        return _transactions[transactionId].approvals[approver];
    }
    
    /**
     * @dev Gets the total number of transactions
     * @return The total number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return _transactionIds.length;
    }
    
    /**
     * @dev Gets a list of transactions with pagination
     * @param offset The starting index
     * @param limit The maximum number of transactions to return
     * @return A list of transaction IDs
     */
    function getTransactions(uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 totalTransactions = _transactionIds.length;
        
        if (offset >= totalTransactions) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalTransactions) {
            end = totalTransactions;
        }
        
        uint256 resultLength = end - offset;
        uint256[] memory result = new uint256[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = _transactionIds[offset + i];
        }
        
        return result;
    }
    
    /**
     * @dev Gets the balance of an asset
     * @param tokenAddress The address of the token (address(0) for ETH)
     * @return The balance of the asset
     */
    function getBalance(address tokenAddress) external view returns (uint256) {
        if (tokenAddress == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(tokenAddress).balanceOf(address(this));
        }
    }
    
    /**
     * @dev Gets a list of all tracked assets
     * @return A list of token addresses
     */
    function getTrackedAssets() external view returns (address[] memory) {
        return _trackedAssets;
    }
    
    /**
     * @dev Gets information about an asset
     * @param tokenAddress The address of the token
     * @return symbol The symbol of the token
     * @return decimals The decimals of the token
     * @return tracked Whether the asset is tracked
     */
    function getAssetInfo(address tokenAddress) external view returns (
        string memory symbol,
        uint8 decimals,
        bool tracked
    ) {
        Asset storage asset = _assets[tokenAddress];
        return (asset.symbol, asset.decimals, asset.tracked);
    }
    
    /**
     * @dev Gets a list of all budget categories
     * @return A list of budget categories
     */
    function getBudgetCategories() external view returns (string[] memory) {
        return _budgetCategories;
    }
    
    /**
     * @dev Gets information about a budget
     * @param category The budget category
     * @return allocation The allocated amount
     * @return spent The spent amount
     * @return remaining The remaining amount
     * @return period The budget period
     * @return active Whether the budget is active
     */
    function getBudgetInfo(string memory category) external view returns (
        uint256 allocation,
        uint256 spent,
        uint256 remaining,
        uint256 period,
        bool active
    ) {
        Budget storage budget = _budgets[category];
        uint256 remainingAmount = budget.allocation > budget.spent ? budget.allocation - budget.spent : 0;
        return (budget.allocation, budget.spent, remainingAmount, budget.period, budget.active);
    }
    
    /**
     * @dev Internal function to add an asset
     * @param tokenAddress The address of the token
     * @param symbol The symbol of the token
     * @param decimals The decimals of the token
     */
    function _addAsset(address tokenAddress, string memory symbol, uint8 decimals) internal {
        _assets[tokenAddress] = Asset({
            tokenAddress: tokenAddress,
            symbol: symbol,
            decimals: decimals,
            tracked: true
        });
        
        _trackedAssets.push(tokenAddress);
        
        emit AssetAdded(tokenAddress, symbol);
    }
    
    /**
     * @dev Internal function to update budget spending
     * @param category The budget category
     * @param amount The amount spent
     */
    function _updateBudgetSpending(string memory category, uint256 amount) internal {
        Budget storage budget = _budgets[category];
        
        if (!budget.active) {
            return;
        }
        
        budget.spent += amount;
        uint256 remaining = budget.allocation > budget.spent ? budget.allocation - budget.spent : 0;
        
        emit BudgetSpent(category, amount, remaining);
    }
    
    /**
     * @dev Checks if a transaction exists
     * @param transactionId The ID of the transaction
     * @return True if the transaction exists, false otherwise
     */
    function _transactionExists(uint256 transactionId) internal view returns (bool) {
        return transactionId > 0 && transactionId < _transactionIdTracker.current();
    }
}
