// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title ForgeToken
 * @dev ERC-20 token for the DAOforge platform with governance capabilities
 * 
 * This token implements:
 * - Standard ERC20 functionality
 * - Burning capability
 * - Permit functionality for gasless approvals
 * - Role-based access control
 * - Pausable functionality for emergency situations
 * - Staking mechanisms for platform benefits
 */
contract ForgeToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Staking related variables
    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        bool active;
    }

    // Staking tiers (in tokens)
    uint256 public constant BRONZE_TIER = 1000 * 10**18;   // 1,000 FORGE
    uint256 public constant SILVER_TIER = 5000 * 10**18;   // 5,000 FORGE
    uint256 public constant GOLD_TIER = 25000 * 10**18;    // 25,000 FORGE
    uint256 public constant PLATINUM_TIER = 100000 * 10**18; // 100,000 FORGE

    // Lock periods (in seconds)
    uint256 public constant FLEXIBLE_LOCK = 0;             // No lock
    uint256 public constant THREE_MONTH_LOCK = 90 days;    // 3 months
    uint256 public constant SIX_MONTH_LOCK = 180 days;     // 6 months
    uint256 public constant TWELVE_MONTH_LOCK = 360 days;  // 12 months

    // Reward multipliers (in basis points, 10000 = 100%)
    uint256 public constant FLEXIBLE_MULTIPLIER = 10000;   // 1.0x
    uint256 public constant THREE_MONTH_MULTIPLIER = 12000; // 1.2x
    uint256 public constant SIX_MONTH_MULTIPLIER = 15000;  // 1.5x
    uint256 public constant TWELVE_MONTH_MULTIPLIER = 20000; // 2.0x

    // Mapping from address to stake info
    mapping(address => StakeInfo) public stakes;
    
    // Total staked amount
    uint256 public totalStaked;

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardDistributed(address indexed user, uint256 amount);

    /**
     * @dev Constructor that initializes the token with name, symbol, and assigns roles to the deployer
     */
    constructor() 
        ERC20("FORGE Token", "FORGE") 
        ERC20Permit("FORGE Token") 
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
    }

    /**
     * @dev Mints new tokens to the specified address
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Pauses all token transfers
     * Requirements:
     * - The caller must have the PAUSER_ROLE
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
     * Requirements:
     * - The caller must have the PAUSER_ROLE
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Override of the _beforeTokenTransfer function to add pausable functionality
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Allows a user to stake tokens for platform benefits
     * @param amount The amount of tokens to stake
     * @param lockPeriod The period to lock the tokens (0, 90 days, 180 days, or 360 days)
     */
    function stake(uint256 amount, uint256 lockPeriod) external {
        require(amount > 0, "Cannot stake 0 tokens");
        require(
            lockPeriod == FLEXIBLE_LOCK || 
            lockPeriod == THREE_MONTH_LOCK || 
            lockPeriod == SIX_MONTH_LOCK || 
            lockPeriod == TWELVE_MONTH_LOCK, 
            "Invalid lock period"
        );
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // If already staking, unstake first
        if (stakes[msg.sender].active) {
            _unstake();
        }
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        // Update stake info
        stakes[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lockPeriod: lockPeriod,
            active: true
        });
        
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, lockPeriod);
    }

    /**
     * @dev Allows a user to unstake their tokens after the lock period
     */
    function unstake() external {
        require(stakes[msg.sender].active, "No active stake");
        require(
            block.timestamp >= stakes[msg.sender].startTime + stakes[msg.sender].lockPeriod,
            "Tokens are still locked"
        );
        
        _unstake();
    }

    /**
     * @dev Internal function to handle unstaking logic
     */
    function _unstake() internal {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.active, "No active stake");
        
        uint256 amount = stakeInfo.amount;
        
        // Reset stake info
        stakeInfo.amount = 0;
        stakeInfo.active = false;
        
        totalStaked -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev Returns the staking tier of an address
     * @param user The address to check
     * @return The staking tier (0=None, 1=Bronze, 2=Silver, 3=Gold, 4=Platinum)
     */
    function getStakingTier(address user) public view returns (uint8) {
        if (!stakes[user].active) return 0;
        
        uint256 amount = stakes[user].amount;
        
        if (amount >= PLATINUM_TIER) return 4;
        if (amount >= GOLD_TIER) return 3;
        if (amount >= SILVER_TIER) return 2;
        if (amount >= BRONZE_TIER) return 1;
        
        return 0;
    }

    /**
     * @dev Returns the reward multiplier for an address based on lock period
     * @param user The address to check
     * @return The reward multiplier in basis points (10000 = 100%)
     */
    function getRewardMultiplier(address user) public view returns (uint256) {
        if (!stakes[user].active) return 0;
        
        uint256 lockPeriod = stakes[user].lockPeriod;
        
        if (lockPeriod == TWELVE_MONTH_LOCK) return TWELVE_MONTH_MULTIPLIER;
        if (lockPeriod == SIX_MONTH_LOCK) return SIX_MONTH_MULTIPLIER;
        if (lockPeriod == THREE_MONTH_LOCK) return THREE_MONTH_MULTIPLIER;
        
        return FLEXIBLE_MULTIPLIER;
    }

    /**
     * @dev Distributes rewards to stakers
     * @param user The address to receive rewards
     * @param amount The base amount of rewards
     * Requirements:
     * - The caller must have the GOVERNANCE_ROLE
     */
    function distributeReward(address user, uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        require(stakes[user].active, "User has no active stake");
        
        uint256 multiplier = getRewardMultiplier(user);
        uint256 adjustedAmount = (amount * multiplier) / 10000;
        
        _mint(user, adjustedAmount);
        
        emit RewardDistributed(user, adjustedAmount);
    }

    /**
     * @dev Returns the fee discount percentage for an address based on staking tier
     * @param user The address to check
     * @return The discount percentage (0-50)
     */
    function getFeeDiscount(address user) external view returns (uint8) {
        uint8 tier = getStakingTier(user);
        
        if (tier == 4) return 50; // Platinum: 50% discount
        if (tier == 3) return 30; // Gold: 30% discount
        if (tier == 2) return 20; // Silver: 20% discount
        if (tier == 1) return 10; // Bronze: 10% discount
        
        return 0; // No discount
    }

    /**
     * @dev Returns the governance weight multiplier for an address based on staking tier
     * @param user The address to check
     * @return The governance weight multiplier in basis points (10000 = 1.0x)
     */
    function getGovernanceMultiplier(address user) external view returns (uint256) {
        uint8 tier = getStakingTier(user);
        
        if (tier == 4) return 15000; // Platinum: 1.5x
        if (tier == 3) return 13000; // Gold: 1.3x
        if (tier == 2) return 12000; // Silver: 1.2x
        if (tier == 1) return 11000; // Bronze: 1.1x
        
        return 10000; // No multiplier (1.0x)
    }
}
