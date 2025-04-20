// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DAOCore.sol";
import "./Governance.sol";
import "./Treasury.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title DAOFactory
 * @dev Factory contract for creating new DAO instances with different templates
 *
 * This contract allows users to:
 * - Create new DAOs based on predefined templates
 * - Register DAOs in a global registry
 * - Manage template configurations
 */
contract DAOFactory is Ownable {
    using Counters for Counters.Counter;
    
    // Counter for DAO IDs
    Counters.Counter private _daoIdCounter;
    
    // Template types
    enum TemplateType {
        INVESTMENT,  // Investment DAO template
        SERVICE,     // Service DAO template
        SOCIAL,      // Social DAO template
        PROTOCOL     // Protocol DAO template
    }
    
    // Template configuration
    struct Template {
        string name;
        string description;
        address coreImplementation;
        address governanceImplementation;
        address treasuryImplementation;
        bool active;
    }
    
    // DAO information
    struct DAOInfo {
        uint256 id;
        string name;
        address coreContract;
        address governanceContract;
        address treasuryContract;
        address tokenContract;
        address creator;
        TemplateType templateType;
        uint256 createdAt;
    }
    
    // Mapping from template type to template configuration
    mapping(TemplateType => Template) public templates;
    
    // Mapping from DAO ID to DAO information
    mapping(uint256 => DAOInfo) public daos;
    
    // Mapping from DAO core address to DAO ID
    mapping(address => uint256) public daoAddressToId;
    
    // Array of all DAO IDs
    uint256[] public allDaoIds;
    
    // Events
    event TemplateAdded(TemplateType indexed templateType, string name);
    event TemplateUpdated(TemplateType indexed templateType, string name);
    event TemplateActivationChanged(TemplateType indexed templateType, bool active);
    event DAOCreated(
        uint256 indexed daoId,
        string name,
        address indexed coreContract,
        address indexed creator,
        TemplateType templateType
    );
    
    /**
     * @dev Constructor that initializes the contract with the contract owner
     */
    constructor() Ownable(msg.sender) {
        // Initialize counter at 1 (0 is reserved for invalid/non-existent DAOs)
        _daoIdCounter.increment();
    }
    
    /**
     * @dev Adds a new template configuration
     * @param templateType The type of template to add
     * @param name The name of the template
     * @param description The description of the template
     * @param coreImplementation The address of the core implementation contract
     * @param governanceImplementation The address of the governance implementation contract
     * @param treasuryImplementation The address of the treasury implementation contract
     */
    function addTemplate(
        TemplateType templateType,
        string memory name,
        string memory description,
        address coreImplementation,
        address governanceImplementation,
        address treasuryImplementation
    ) external onlyOwner {
        require(coreImplementation != address(0), "Core implementation cannot be zero address");
        require(governanceImplementation != address(0), "Governance implementation cannot be zero address");
        require(treasuryImplementation != address(0), "Treasury implementation cannot be zero address");
        
        templates[templateType] = Template({
            name: name,
            description: description,
            coreImplementation: coreImplementation,
            governanceImplementation: governanceImplementation,
            treasuryImplementation: treasuryImplementation,
            active: true
        });
        
        emit TemplateAdded(templateType, name);
    }
    
    /**
     * @dev Updates an existing template configuration
     * @param templateType The type of template to update
     * @param name The new name of the template
     * @param description The new description of the template
     * @param coreImplementation The new address of the core implementation contract
     * @param governanceImplementation The new address of the governance implementation contract
     * @param treasuryImplementation The new address of the treasury implementation contract
     */
    function updateTemplate(
        TemplateType templateType,
        string memory name,
        string memory description,
        address coreImplementation,
        address governanceImplementation,
        address treasuryImplementation
    ) external onlyOwner {
        require(coreImplementation != address(0), "Core implementation cannot be zero address");
        require(governanceImplementation != address(0), "Governance implementation cannot be zero address");
        require(treasuryImplementation != address(0), "Treasury implementation cannot be zero address");
        
        Template storage template = templates[templateType];
        
        template.name = name;
        template.description = description;
        template.coreImplementation = coreImplementation;
        template.governanceImplementation = governanceImplementation;
        template.treasuryImplementation = treasuryImplementation;
        
        emit TemplateUpdated(templateType, name);
    }
    
    /**
     * @dev Changes the activation status of a template
     * @param templateType The type of template to update
     * @param active The new activation status
     */
    function setTemplateActive(TemplateType templateType, bool active) external onlyOwner {
        templates[templateType].active = active;
        
        emit TemplateActivationChanged(templateType, active);
    }
    
    /**
     * @dev Creates a new DAO instance based on a template
     * @param templateType The type of template to use
     * @param name The name of the DAO
     * @param tokenAddress The address of the token contract (optional, can be address(0))
     * @param votingPeriod The voting period for proposals in seconds
     * @param quorumPercentage The quorum percentage required for proposals (1-100)
     * @param proposalThreshold The minimum tokens required to create a proposal
     * @param initialMembers Array of initial member addresses
     * @param initialMemberRoles Array of initial member roles (must match length of initialMembers)
     * @return daoId The ID of the newly created DAO
     * @return coreContract The address of the core contract
     * @return governanceContract The address of the governance contract
     * @return treasuryContract The address of the treasury contract
     */
    function createDAO(
        TemplateType templateType,
        string memory name,
        address tokenAddress,
        uint256 votingPeriod,
        uint8 quorumPercentage,
        uint256 proposalThreshold,
        address[] memory initialMembers,
        uint8[] memory initialMemberRoles
    ) external returns (
        uint256 daoId,
        address coreContract,
        address governanceContract,
        address treasuryContract
    ) {
        Template memory template = templates[templateType];
        require(template.active, "Template is not active");
        require(initialMembers.length == initialMemberRoles.length, "Members and roles length mismatch");
        require(quorumPercentage > 0 && quorumPercentage <= 100, "Quorum must be between 1 and 100");
        
        // Create DAO ID
        daoId = _daoIdCounter.current();
        _daoIdCounter.increment();
        
        // Clone contracts using minimal proxy pattern
        coreContract = Clones.clone(template.coreImplementation);
        governanceContract = Clones.clone(template.governanceImplementation);
        treasuryContract = Clones.clone(template.treasuryImplementation);
        
        // Initialize contracts
        DAOCore(coreContract).initialize(
            name,
            msg.sender,
            governanceContract,
            treasuryContract,
            tokenAddress
        );
        
        Governance(governanceContract).initialize(
            coreContract,
            tokenAddress,
            votingPeriod,
            quorumPercentage,
            proposalThreshold
        );
        
        Treasury(treasuryContract).initialize(
            coreContract,
            governanceContract
        );
        
        // Add initial members
        for (uint256 i = 0; i < initialMembers.length; i++) {
            DAOCore(coreContract).addMember(initialMembers[i], initialMemberRoles[i]);
        }
        
        // Register DAO in registry
        daos[daoId] = DAOInfo({
            id: daoId,
            name: name,
            coreContract: coreContract,
            governanceContract: governanceContract,
            treasuryContract: treasuryContract,
            tokenContract: tokenAddress,
            creator: msg.sender,
            templateType: templateType,
            createdAt: block.timestamp
        });
        
        daoAddressToId[coreContract] = daoId;
        allDaoIds.push(daoId);
        
        emit DAOCreated(daoId, name, coreContract, msg.sender, templateType);
        
        return (daoId, coreContract, governanceContract, treasuryContract);
    }
    
    /**
     * @dev Returns the total number of DAOs created
     * @return The total number of DAOs
     */
    function getTotalDAOs() external view returns (uint256) {
        return allDaoIds.length;
    }
    
    /**
     * @dev Returns a list of DAOs with pagination
     * @param offset The starting index
     * @param limit The maximum number of DAOs to return
     * @return A list of DAO IDs
     */
    function getDAOs(uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 totalDAOs = allDaoIds.length;
        
        if (offset >= totalDAOs) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalDAOs) {
            end = totalDAOs;
        }
        
        uint256 resultLength = end - offset;
        uint256[] memory result = new uint256[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = allDaoIds[offset + i];
        }
        
        return result;
    }
    
    /**
     * @dev Returns the DAOs created by a specific address
     * @param creator The address of the creator
     * @return A list of DAO IDs
     */
    function getDAOsByCreator(address creator) external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Count DAOs created by the address
        for (uint256 i = 0; i < allDaoIds.length; i++) {
            if (daos[allDaoIds[i]].creator == creator) {
                count++;
            }
        }
        
        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        // Fill result array
        for (uint256 i = 0; i < allDaoIds.length; i++) {
            if (daos[allDaoIds[i]].creator == creator) {
                result[index] = allDaoIds[i];
                index++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Returns the DAOs of a specific template type
     * @param templateType The template type
     * @return A list of DAO IDs
     */
    function getDAOsByTemplate(TemplateType templateType) external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Count DAOs of the template type
        for (uint256 i = 0; i < allDaoIds.length; i++) {
            if (daos[allDaoIds[i]].templateType == templateType) {
                count++;
            }
        }
        
        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        // Fill result array
        for (uint256 i = 0; i < allDaoIds.length; i++) {
            if (daos[allDaoIds[i]].templateType == templateType) {
                result[index] = allDaoIds[i];
                index++;
            }
        }
        
        return result;
    }
}
