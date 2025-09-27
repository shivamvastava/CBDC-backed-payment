// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title WINR - Wrapped Indian Rupee Token
 * @dev ERC20 token representing wrapped Indian Rupee (wINR)
 * @notice This token is designed for use in CBDC-backed payment systems
 * with built-in compliance features for regulatory requirements
 */
contract WINR is ERC20, Ownable, Pausable {
    // Maximum supply of wINR tokens (1 billion tokens with 18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    
    // Mapping to track blacklisted addresses
    mapping(address => bool) public blacklisted;
    
    // Events for compliance tracking
    event AddressBlacklisted(address indexed account, bool status);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    
    // Modifier to check if address is not blacklisted
    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "WINR: Address is blacklisted");
        _;
    }
    
    /**
     * @dev Constructor that initializes the wINR token
     * @param initialSupply Initial supply of tokens to mint to the owner
     */
    constructor(uint256 initialSupply) ERC20("Wrapped Indian Rupee", "wINR") Ownable(msg.sender) {
        require(initialSupply <= MAX_SUPPLY, "WINR: Initial supply exceeds maximum");
        
        // Mint initial supply to the owner
        _mint(msg.sender, initialSupply);
    }
    
    /**
     * @dev Mint new tokens (only owner)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "WINR: Minting would exceed maximum supply");
        require(to != address(0), "WINR: Cannot mint to zero address");
        require(!blacklisted[to], "WINR: Cannot mint to blacklisted address");
        
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    /**
     * @dev Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }
    
    /**
     * @dev Burn tokens from specified address (only owner)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }
    
    /**
     * @dev Add or remove address from blacklist (only owner)
     * @param account Address to blacklist/unblacklist
     * @param status True to blacklist, false to remove from blacklist
     */
    function updateBlacklist(address account, bool status) external onlyOwner {
        require(account != address(0), "WINR: Cannot blacklist zero address");
        blacklisted[account] = status;
        emit AddressBlacklisted(account, status);
    }
    
    /**
     * @dev Pause token transfers (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override _update to include blacklist and pause checks
     * @dev This replaces _beforeTokenTransfer in OpenZeppelin v5
     */
    function _update(address from, address to, uint256 value) internal override {
        // Check if contract is paused
        require(!paused(), "WINR: Token transfers are paused");
        
        // Check blacklist status (except for minting and burning)
        if (from != address(0)) {
            require(!blacklisted[from], "WINR: Sender is blacklisted");
        }
        if (to != address(0)) {
            require(!blacklisted[to], "WINR: Recipient is blacklisted");
        }
        
        super._update(from, to, value);
    }
    
    /**
     * @dev Get the number of decimals for the token
     * @return Number of decimals (18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    /**
     * @dev Get the maximum supply of tokens
     * @return Maximum supply
     */
    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }
    
    /**
     * @dev Check if an address is blacklisted
     * @param account Address to check
     * @return True if blacklisted, false otherwise
     */
    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }
    
    /**
     * @dev Get the remaining mintable supply
     * @return Remaining mintable amount
     */
    function getRemainingMintableSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }
}
