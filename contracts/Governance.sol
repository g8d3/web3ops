// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/counter/Counters.sol";
import "./DAOCore.sol";

/**
 * @title Governance
 * @dev Contract for DAO governance functionality
 *
 * This contract implements:
 * - Proposal creation and management
 * - Voting mechanisms
 * - Proposal execution
 * - Delegation functionality
 */
contract Governance is Initializable {
    using Counters for Counters.Counter;
    
    // Proposal states
    enum ProposalState {
        Pending,    // Proposal is created but voting has not started
        Active,     // Voting is active
        Canceled,   // Proposal was canceled
        Defeated,   // Proposal was defeated (quorum not reached or majority against)
        Succeeded,  // Proposal was approved but not yet executed
        Executed,   // Proposal was executed
        Expired     // Voting period ended without reaching quorum
    }
    
    // Vote types
    enum VoteType {
        Against,    // Vote against the proposal
        For,        // Vote for the proposal
        Abstain     // Abstain from voting
    }
    
    // Proposal structure
    struct Proposal {
        uint256 id;                     // Unique identifier
        address proposer;               // Address that created the proposal
        string title;                   // Title of the proposal
        string description;             // IPFS hash of the proposal description
        uint256 startTime;              // When voting begins
        uint256 endTime;                // When voting ends
        bool executed;                  // Whether the proposal has been executed
        bool canceled;                  // Whether the proposal has been canceled
        uint256 forVotes;               // Number of votes for the proposal
        uint256 againstVotes;           // Number of votes against the proposal
        uint256 abstainVotes;           // Number of abstain votes
        mapping(address => Receipt) receipts; // Voting receipts by voter
        address[] targets;              // Target addresses for calls
        uint256[] values;               // ETH values for calls
        bytes[] calldatas;              // Calldata for calls
        string[] signatures;            // Function signatures for calls
    }
    
    // Vote receipt
    struct Receipt {
        bool hasVoted;                  // Whether the address has voted
        VoteType support;               // How the address voted
        uint256 votes;                  // Number of votes cast
    }
    
    // Proposal summary (for external view)
    struct ProposalSummary {
        uint256 id;
        address proposer;
        string title;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool canceled;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        ProposalState state;
    }
    
    // Contract references
    address public daoCore;
    address public tokenAddress;
    
    // Governance parameters
    uint256 public votingPeriod;        // Duration of voting in seconds
    uint8 public quorumPercentage;      // Percentage of total supply needed for quorum (1-100)
    uint256 public proposalThreshold;   // Minimum tokens needed to create a proposal
    
    // Proposal tracking
    Counters.Counter private _proposalIdTracker;
    mapping(uint256 => Proposal) private _proposals;
    uint256[] private _proposalIds;
    
    // Delegation tracking
    mapping(address => address) private _delegates;
    
    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime
    );
    event ProposalCanceled(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId);
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 weight
    );
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );
    event GovernanceParametersUpdated(
        uint256 votingPeriod,
        uint8 quorumPercentage,
        uint256 proposalThreshold
    );
    
    /**
     * @dev Modifier to check if the caller is a member
     */
    modifier onlyMember() {
        require(DAOCore(daoCore).isMember(msg.sender), "Governance: caller is not a member");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is an admin
     */
    modifier onlyAdmin() {
        require(DAOCore(daoCore).isAdmin(msg.sender), "Governance: caller is not an admin");
        _;
    }
    
    /**
     * @dev Initializes the contract with initial values
     * @param _daoCore The address of the DAO core contract
     * @param _tokenAddress The address of the token contract (optional, can be address(0))
     * @param _votingPeriod The voting period in seconds
     * @param _quorumPercentage The quorum percentage (1-100)
     * @param _proposalThreshold The proposal threshold
     */
    function initialize(
        address _daoCore,
        address _tokenAddress,
        uint256 _votingPeriod,
        uint8 _quorumPercentage,
        uint256 _proposalThreshold
    ) external initializer {
        require(_daoCore != address(0), "Governance: DAO core cannot be zero address");
        require(_quorumPercentage > 0 && _quorumPercentage <= 100, "Governance: quorum must be between 1 and 100");
        require(_votingPeriod > 0, "Governance: voting period must be greater than 0");
        
        daoCore = _daoCore;
        tokenAddress = _tokenAddress;
        votingPeriod = _votingPeriod;
        quorumPercentage = _quorumPercentage;
        proposalThreshold = _proposalThreshold;
        
        // Start proposal IDs at 1
        _proposalIdTracker.increment();
    }
    
    /**
     * @dev Updates the governance parameters
     * @param _votingPeriod The new voting period in seconds
     * @param _quorumPercentage The new quorum percentage (1-100)
     * @param _proposalThreshold The new proposal threshold
     */
    function updateGovernanceParameters(
        uint256 _votingPeriod,
        uint8 _quorumPercentage,
        uint256 _proposalThreshold
    ) external onlyAdmin {
        require(_quorumPercentage > 0 && _quorumPercentage <= 100, "Governance: quorum must be between 1 and 100");
        require(_votingPeriod > 0, "Governance: voting period must be greater than 0");
        
        votingPeriod = _votingPeriod;
        quorumPercentage = _quorumPercentage;
        proposalThreshold = _proposalThreshold;
        
        emit GovernanceParametersUpdated(_votingPeriod, _quorumPercentage, _proposalThreshold);
    }
    
    /**
     * @dev Creates a new proposal
     * @param title The title of the proposal
     * @param description The IPFS hash of the proposal description
     * @param targets The target addresses for calls
     * @param values The ETH values for calls
     * @param signatures The function signatures for calls
     * @param calldatas The calldata for calls
     * @param startTime The time when voting begins (0 for immediate start)
     * @return The ID of the newly created proposal
     */
    function propose(
        string memory title,
        string memory description,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        uint256 startTime
    ) external onlyMember returns (uint256) {
        require(targets.length > 0, "Governance: proposal must have actions");
        require(
            targets.length == values.length &&
            targets.length == signatures.length &&
            targets.length == calldatas.length,
            "Governance: proposal function information mismatch"
        );
        
        // Check proposal threshold if token is used
        if (tokenAddress != address(0)) {
            uint256 proposerVotes = getVotes(msg.sender);
            require(
                proposerVotes >= proposalThreshold,
                "Governance: proposer votes below threshold"
            );
        }
        
        uint256 proposalId = _proposalIdTracker.current();
        _proposalIdTracker.increment();
        
        // Set start time to current time if not specified
        if (startTime == 0) {
            startTime = block.timestamp;
        } else {
            require(startTime >= block.timestamp, "Governance: start time cannot be in the past");
        }
        
        uint256 endTime = startTime + votingPeriod;
        
        Proposal storage proposal = _proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.title = title;
        proposal.description = description;
        proposal.startTime = startTime;
        proposal.endTime = endTime;
        
        for (uint256 i = 0; i < targets.length; i++) {
            proposal.targets.push(targets[i]);
            proposal.values.push(values[i]);
            proposal.signatures.push(signatures[i]);
            proposal.calldatas.push(calldatas[i]);
        }
        
        _proposalIds.push(proposalId);
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            title,
            targets,
            values,
            signatures,
            calldatas,
            startTime,
            endTime
        );
        
        return proposalId;
    }
    
    /**
     * @dev Cancels a proposal
     * @param proposalId The ID of the proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        require(
            state(proposalId) == ProposalState.Pending || 
            state(proposalId) == ProposalState.Active,
            "Governance: proposal not active"
        );
        
        Proposal storage proposal = _proposals[proposalId];
        
        // Only proposer or admin can cancel
        require(
            proposal.proposer == msg.sender || DAOCore(daoCore).isAdmin(msg.sender),
            "Governance: only proposer or admin can cancel"
        );
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId);
    }
    
    /**
     * @dev Executes a proposal
     * @param proposalId The ID of the proposal to execute
     */
    function execute(uint256 proposalId) external payable {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "Governance: proposal not successful"
        );
        
        Proposal storage proposal = _proposals[proposalId];
        proposal.executed = true;
        
        // Execute each action
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bytes memory callData;
            
            if (bytes(proposal.signatures[i]).length > 0) {
                // If signature is provided, encode with signature
                callData = abi.encodePacked(
                    bytes4(keccak256(bytes(proposal.signatures[i]))),
                    proposal.calldatas[i]
                );
            } else {
                // Otherwise use calldata directly
                callData = proposal.calldatas[i];
            }
            
            // Execute the call
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(callData);
            require(success, "Governance: transaction execution reverted");
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    /**
     * @dev Casts a vote on a proposal
     * @param proposalId The ID of the proposal
     * @param support The vote type (0=Against, 1=For, 2=Abstain)
     */
    function castVote(uint256 proposalId, uint8 support) external onlyMember {
        require(state(proposalId) == ProposalState.Active, "Governance: voting is closed");
        require(support <= uint8(VoteType.Abstain), "Governance: invalid vote type");
        
        Proposal storage proposal = _proposals[proposalId];
        Receipt storage receipt = proposal.receipts[msg.sender];
        
        require(!receipt.hasVoted, "Governance: already voted");
        
        uint256 votes;
        
        // If token is used, get voting weight from token
        if (tokenAddress != address(0)) {
            votes = getVotes(msg.sender);
        } else {
            // If no token, each member gets 1 vote
            votes = 1;
        }
        
        if (support == uint8(VoteType.Against)) {
            proposal.againstVotes += votes;
        } else if (support == uint8(VoteType.For)) {
            proposal.forVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }
        
        receipt.hasVoted = true;
        receipt.support = VoteType(support);
        receipt.votes = votes;
        
        emit VoteCast(msg.sender, proposalId, support, votes);
    }
    
    /**
     * @dev Delegates voting power to another address
     * @param delegatee The address to delegate to
     */
    function delegate(address delegatee) external onlyMember {
        require(tokenAddress != address(0), "Governance: token not configured");
        require(delegatee != address(0), "Governance: cannot delegate to zero address");
        
        address currentDelegate = _delegates[msg.sender];
        _delegates[msg.sender] = delegatee;
        
        emit DelegateChanged(msg.sender, currentDelegate, delegatee);
        
        // If token supports ERC20Votes, use its delegation
        if (_isERC20Votes(tokenAddress)) {
            ERC20Votes(tokenAddress).delegate(delegatee);
        }
    }
    
    /**
     * @dev Gets the current state of a proposal
     * @param proposalId The ID of the proposal
     * @return The current state of the proposal
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(_proposalExists(proposalId), "Governance: proposal does not exist");
        
        Proposal storage proposal = _proposals[proposalId];
        
        if (proposal.canceled) {
            return ProposalState.Canceled;
        }
        
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        
        if (block.timestamp < proposal.startTime) {
            return ProposalState.Pending;
        }
        
        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        }
        
        // Check if quorum was reached
        if (!_quorumReached(proposalId)) {
            return ProposalState.Expired;
        }
        
        // Check if proposal succeeded
        if (_proposalSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }
    
    /**
     * @dev Gets the voting weight of an address
     * @param account The address to check
     * @return The voting weight
     */
    function getVotes(address account) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            // If no token, each member gets 1 vote
            return DAOCore(daoCore).isMember(account) ? 1 : 0;
        }
        
        // If token supports ERC20Votes, use its getVotes function
        if (_isERC20Votes(tokenAddress)) {
            return ERC20Votes(tokenAddress).getVotes(account);
        }
        
        // Otherwise use token balance
        return IERC20(tokenAddress).balanceOf(account);
    }
    
    /**
     * @dev Gets the delegate of an address
     * @param account The address to check
     * @return The delegate address
     */
    function delegates(address account) external view returns (address) {
        // If token supports ERC20Votes, use its delegates function
        if (tokenAddress != address(0) && _isERC20Votes(tokenAddress)) {
            return ERC20Votes(tokenAddress).delegates(account);
        }
        
        return _delegates[account];
    }
    
    /**
     * @dev Gets the receipt for a vote
     * @param proposalId The ID of the proposal
     * @param voter The address of the voter
     * @return hasVoted Whether the voter has voted
     * @return support The vote type
     * @return votes The number of votes cast
     */
    function getReceipt(uint256 proposalId, address voter) external view returns (
        bool hasVoted,
        uint8 support,
        uint256 votes
    ) {
        require(_proposalExists(proposalId), "Governance: proposal does not exist");
        
        Receipt storage receipt = _proposals[proposalId].receipts[voter];
        return (receipt.hasVoted, uint8(receipt.support), receipt.votes);
    }
    
    /**
     * @dev Gets a proposal summary
     * @param proposalId The ID of the proposal
     * @return A proposal summary struct
     */
    function getProposal(uint256 proposalId) external view returns (ProposalSummary memory) {
        require(_proposalExists(proposalId), "Governance: proposal does not exist");
        
        Proposal storage proposal = _proposals[proposalId];
        
        return ProposalSummary({
            id: proposal.id,
            proposer: proposal.proposer,
            title: proposal.title,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            executed: proposal.executed,
            canceled: proposal.canceled,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            abstainVotes: proposal.abstainVotes,
            state: state(proposalId)
        });
    }
    
    /**
     * @dev Gets the proposal actions
     * @param proposalId The ID of the proposal
     * @return targets The target addresses
     * @return values The ETH values
     * @return signatures The function signatures
     * @return calldatas The calldata
     */
    function getActions(uint256 proposalId) external view returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) {
        require(_proposalExists(proposalId), "Governance: proposal does not exist");
        
        Proposal storage proposal = _proposals[proposalId];
        
        return (
            proposal.targets,
            proposal.values,
            proposal.signatures,
            proposal.calldatas
        );
    }
    
    /**
     * @dev Gets the total number of proposals
     * @return The total number of proposals
     */
    function getProposalCount() external view returns (uint256) {
        return _proposalIds.length;
    }
    
    /**
     * @dev Gets a list of proposals with pagination
     * @param offset The starting index
     * @param limit The maximum number of proposals to return
     * @return A list of proposal IDs
     */
    function getProposals(uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 totalProposals = _proposalIds.length;
        
        if (offset >= totalProposals) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalProposals) {
            end = totalProposals;
        }
        
        uint256 resultLength = end - offset;
        uint256[] memory result = new uint256[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = _proposalIds[offset + i];
        }
        
        return result;
    }
    
    /**
     * @dev Checks if a proposal exists
     * @param proposalId The ID of the proposal
     * @return True if the proposal exists, false otherwise
     */
    function _proposalExists(uint256 proposalId) internal view returns (bool) {
        return proposalId > 0 && proposalId < _proposalIdTracker.current();
    }
    
    /**
     * @dev Checks if a proposal has reached quorum
     * @param proposalId The ID of the proposal
     * @return True if quorum is reached, false otherwise
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        
        if (tokenAddress == address(0)) {
            // If no token, quorum is based on member count
            uint256 memberCount = DAOCore(daoCore).getMemberCount();
            return totalVotes >= (memberCount * quorumPercentage) / 100;
        } else {
            // If token is used, quorum is based on total supply
            uint256 totalSupply = IERC20(tokenAddress).totalSupply();
            return totalVotes >= (totalSupply * quorumPercentage) / 100;
        }
    }
    
    /**
     * @dev Checks if a proposal has succeeded
     * @param proposalId The ID of the proposal
     * @return True if the proposal succeeded, false otherwise
     */
    function _proposalSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes;
    }
    
    /**
     * @dev Checks if a token implements ERC20Votes
     * @param token The token address
     * @return True if the token implements ERC20Votes, false otherwise
     */
    function _isERC20Votes(address token) internal view returns (bool) {
        try ERC20Votes(token).delegates(address(this)) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
