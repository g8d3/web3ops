// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DAOCore
 * @dev Core contract for DAO functionality
 *
 * This contract serves as the central hub for each DAO instance, managing:
 * - Member management and roles
 * - Integration with governance and treasury contracts
 * - DAO metadata and configuration
 * - Access control for various DAO operations
 */
contract DAOCore is Initializable, AccessControl {
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant CONTRIBUTOR_ROLE = keccak256("CONTRIBUTOR_ROLE");
    
    // DAO metadata
    string public name;
    string public description;
    string public logoURI;
    string public websiteURL;
    
    // Contract references
    address public governanceContract;
    address public treasuryContract;
    address public tokenContract;
    
    // Member information
    struct Member {
        bool exists;
        uint256 joinedAt;
        string metadata; // IPFS hash for additional member data
    }
    
    // Mapping from address to member information
    mapping(address => Member) public members;
    
    // Array of all member addresses
    address[] public memberAddresses;
    
    // Events
    event MemberAdded(address indexed member, bytes32 role);
    event MemberRemoved(address indexed member);
    event RoleGranted(address indexed member, bytes32 role);
    event RoleRevoked(address indexed member, bytes32 role);
    event MetadataUpdated(string name, string description);
    event ContractAddressUpdated(string contractType, address indexed contractAddress);
    
    /**
     * @dev Modifier to check if the caller is a member
     */
    modifier onlyMember() {
        require(hasRole(MEMBER_ROLE, msg.sender), "DAOCore: caller is not a member");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is an admin
     */
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "DAOCore: caller is not an admin");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is the governance contract
     */
    modifier onlyGovernance() {
        require(msg.sender == governanceContract, "DAOCore: caller is not the governance contract");
        _;
    }
    
    /**
     * @dev Modifier to check if the caller is the treasury contract
     */
    modifier onlyTreasury() {
        require(msg.sender == treasuryContract, "DAOCore: caller is not the treasury contract");
        _;
    }
    
    /**
     * @dev Initializes the contract with initial values
     * @param _name The name of the DAO
     * @param _admin The address of the initial admin
     * @param _governanceContract The address of the governance contract
     * @param _treasuryContract The address of the treasury contract
     * @param _tokenContract The address of the token contract (optional, can be address(0))
     */
    function initialize(
        string memory _name,
        address _admin,
        address _governanceContract,
        address _treasuryContract,
        address _tokenContract
    ) external initializer {
        require(_admin != address(0), "DAOCore: admin cannot be zero address");
        require(_governanceContract != address(0), "DAOCore: governance contract cannot be zero address");
        require(_treasuryContract != address(0), "DAOCore: treasury contract cannot be zero address");
        
        name = _name;
        governanceContract = _governanceContract;
        treasuryContract = _treasuryContract;
        tokenContract = _tokenContract;
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(MEMBER_ROLE, _admin);
        _grantRole(GOVERNANCE_ROLE, _governanceContract);
        _grantRole(TREASURY_ROLE, _treasuryContract);
        
        // Add admin as first member
        members[_admin] = Member({
            exists: true,
            joinedAt: block.timestamp,
            metadata: ""
        });
        
        memberAddresses.push(_admin);
        
        emit MemberAdded(_admin, ADMIN_ROLE);
        emit ContractAddressUpdated("governance", _governanceContract);
        emit ContractAddressUpdated("treasury", _treasuryContract);
        if (_tokenContract != address(0)) {
            emit ContractAddressUpdated("token", _tokenContract);
        }
    }
    
    /**
     * @dev Updates the DAO metadata
     * @param _name The new name of the DAO
     * @param _description The new description of the DAO
     * @param _logoURI The new logo URI of the DAO
     * @param _websiteURL The new website URL of the DAO
     */
    function updateMetadata(
        string memory _name,
        string memory _description,
        string memory _logoURI,
        string memory _websiteURL
    ) external onlyAdmin {
        name = _name;
        description = _description;
        logoURI = _logoURI;
        websiteURL = _websiteURL;
        
        emit MetadataUpdated(_name, _description);
    }
    
    /**
     * @dev Updates the governance contract address
     * @param _governanceContract The new governance contract address
     */
    function updateGovernanceContract(address _governanceContract) external onlyAdmin {
        require(_governanceContract != address(0), "DAOCore: governance contract cannot be zero address");
        
        // Revoke role from old contract
        _revokeRole(GOVERNANCE_ROLE, governanceContract);
        
        // Update contract address
        governanceContract = _governanceContract;
        
        // Grant role to new contract
        _grantRole(GOVERNANCE_ROLE, _governanceContract);
        
        emit ContractAddressUpdated("governance", _governanceContract);
    }
    
    /**
     * @dev Updates the treasury contract address
     * @param _treasuryContract The new treasury contract address
     */
    function updateTreasuryContract(address _treasuryContract) external onlyAdmin {
        require(_treasuryContract != address(0), "DAOCore: treasury contract cannot be zero address");
        
        // Revoke role from old contract
        _revokeRole(TREASURY_ROLE, treasuryContract);
        
        // Update contract address
        treasuryContract = _treasuryContract;
        
        // Grant role to new contract
        _grantRole(TREASURY_ROLE, _treasuryContract);
        
        emit ContractAddressUpdated("treasury", _treasuryContract);
    }
    
    /**
     * @dev Updates the token contract address
     * @param _tokenContract The new token contract address
     */
    function updateTokenContract(address _tokenContract) external onlyAdmin {
        tokenContract = _tokenContract;
        
        emit ContractAddressUpdated("token", _tokenContract);
    }
    
    /**
     * @dev Adds a new member to the DAO
     * @param _member The address of the new member
     * @param _roleType The role type to assign (0=Member, 1=Contributor, 2=Admin)
     */
    function addMember(address _member, uint8 _roleType) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == governanceContract,
            "DAOCore: caller is not authorized"
        );
        require(_member != address(0), "DAOCore: member cannot be zero address");
        require(!members[_member].exists, "DAOCore: member already exists");
        
        // Add member
        members[_member] = Member({
            exists: true,
            joinedAt: block.timestamp,
            metadata: ""
        });
        
        memberAddresses.push(_member);
        
        // Grant roles based on role type
        _grantRole(MEMBER_ROLE, _member);
        
        bytes32 role = MEMBER_ROLE;
        
        if (_roleType == 1) {
            _grantRole(CONTRIBUTOR_ROLE, _member);
            role = CONTRIBUTOR_ROLE;
        } else if (_roleType == 2) {
            _grantRole(ADMIN_ROLE, _member);
            role = ADMIN_ROLE;
        }
        
        emit MemberAdded(_member, role);
    }
    
    /**
     * @dev Removes a member from the DAO
     * @param _member The address of the member to remove
     */
    function removeMember(address _member) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == governanceContract,
            "DAOCore: caller is not authorized"
        );
        require(members[_member].exists, "DAOCore: member does not exist");
        require(_member != msg.sender, "DAOCore: cannot remove self");
        
        // Remove member
        members[_member].exists = false;
        
        // Revoke all roles
        _revokeRole(MEMBER_ROLE, _member);
        _revokeRole(CONTRIBUTOR_ROLE, _member);
        _revokeRole(ADMIN_ROLE, _member);
        
        // Remove from array (note: this doesn't preserve order but is gas efficient)
        for (uint256 i = 0; i < memberAddresses.length; i++) {
            if (memberAddresses[i] == _member) {
                memberAddresses[i] = memberAddresses[memberAddresses.length - 1];
                memberAddresses.pop();
                break;
            }
        }
        
        emit MemberRemoved(_member);
    }
    
    /**
     * @dev Grants a role to a member
     * @param _member The address of the member
     * @param _role The role to grant
     */
    function grantRole(address _member, bytes32 _role) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == governanceContract,
            "DAOCore: caller is not authorized"
        );
        require(members[_member].exists, "DAOCore: member does not exist");
        require(
            _role == MEMBER_ROLE || _role == CONTRIBUTOR_ROLE || _role == ADMIN_ROLE,
            "DAOCore: invalid role"
        );
        
        _grantRole(_role, _member);
        
        emit RoleGranted(_member, _role);
    }
    
    /**
     * @dev Revokes a role from a member
     * @param _member The address of the member
     * @param _role The role to revoke
     */
    function revokeRole(address _member, bytes32 _role) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == governanceContract,
            "DAOCore: caller is not authorized"
        );
        require(members[_member].exists, "DAOCore: member does not exist");
        require(
            _role == MEMBER_ROLE || _role == CONTRIBUTOR_ROLE || _role == ADMIN_ROLE,
            "DAOCore: invalid role"
        );
        
        // Cannot revoke MEMBER_ROLE if member still has other roles
        if (_role == MEMBER_ROLE) {
            require(
                !hasRole(CONTRIBUTOR_ROLE, _member) && !hasRole(ADMIN_ROLE, _member),
                "DAOCore: cannot revoke member role while other roles exist"
            );
        }
        
        _revokeRole(_role, _member);
        
        emit RoleRevoked(_member, _role);
    }
    
    /**
     * @dev Updates a member's metadata
     * @param _member The address of the member
     * @param _metadata The new metadata (IPFS hash)
     */
    function updateMemberMetadata(address _member, string memory _metadata) external {
        require(
            _member == msg.sender || hasRole(ADMIN_ROLE, msg.sender),
            "DAOCore: caller is not authorized"
        );
        require(members[_member].exists, "DAOCore: member does not exist");
        
        members[_member].metadata = _metadata;
    }
    
    /**
     * @dev Returns the total number of members
     * @return The total number of members
     */
    function getMemberCount() external view returns (uint256) {
        return memberAddresses.length;
    }
    
    /**
     * @dev Returns a list of members with pagination
     * @param offset The starting index
     * @param limit The maximum number of members to return
     * @return A list of member addresses
     */
    function getMembers(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 totalMembers = memberAddresses.length;
        
        if (offset >= totalMembers) {
            return new address[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalMembers) {
            end = totalMembers;
        }
        
        uint256 resultLength = end - offset;
        address[] memory result = new address[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = memberAddresses[offset + i];
        }
        
        return result;
    }
    
    /**
     * @dev Checks if an address is a member
     * @param _address The address to check
     * @return True if the address is a member, false otherwise
     */
    function isMember(address _address) external view returns (bool) {
        return members[_address].exists && hasRole(MEMBER_ROLE, _address);
    }
    
    /**
     * @dev Checks if an address is an admin
     * @param _address The address to check
     * @return True if the address is an admin, false otherwise
     */
    function isAdmin(address _address) external view returns (bool) {
        return members[_address].exists && hasRole(ADMIN_ROLE, _address);
    }
    
    /**
     * @dev Checks if an address is a contributor
     * @param _address The address to check
     * @return True if the address is a contributor, false otherwise
     */
    function isContributor(address _address) external view returns (bool) {
        return members[_address].exists && hasRole(CONTRIBUTOR_ROLE, _address);
    }
    
    /**
     * @dev Returns the token balance of the DAO
     * @return The token balance
     */
    function getTokenBalance() external view returns (uint256) {
        if (tokenContract == address(0)) {
            return 0;
        }
        
        return IERC20(tokenContract).balanceOf(address(this));
    }
    
    /**
     * @dev Returns the token balance of a member
     * @param _member The address of the member
     * @return The token balance
     */
    function getMemberTokenBalance(address _member) external view returns (uint256) {
        if (tokenContract == address(0)) {
            return 0;
        }
        
        return IERC20(tokenContract).balanceOf(_member);
    }
}
