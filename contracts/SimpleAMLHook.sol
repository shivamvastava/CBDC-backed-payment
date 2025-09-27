// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleAMLHook - Simplified AML compliance contract without Uniswap V4 dependencies
 * @dev Basic AML checking functionality for CBDC compliance
 */
contract SimpleAMLHook is Ownable {
    // wINR token address
    address public immutable wINR;
    
    // Mapping to track blacklisted addresses
    mapping(address => bool) public blacklisted;
    
    // Mapping to track authorized tokens that can be converted to wINR
    mapping(address => bool) public authorizedTokens;
    
    // Mapping to store conversion rates (token => rate per wINR)
    mapping(address => uint256) public conversionRates;
    
    // Events for compliance and monitoring
    event AddressBlacklisted(address indexed account, bool status);
    event TokenAuthorized(address indexed token, bool status);
    event ConversionRateUpdated(address indexed token, uint256 rate);
    event SwapBlocked(address indexed user, string reason);
    event TokenConverted(address indexed user, address indexed fromToken, uint256 amount, uint256 wINRAmount);
    
    /**
     * @dev Constructor
     * @param _wINR wINR token address
     */
    constructor(address _wINR) Ownable(msg.sender) {
        require(_wINR != address(0), "SimpleAMLHook: Invalid wINR address");
        wINR = _wINR;
    }
    
    /**
     * @dev Check AML compliance for addresses
     * @param sender Address initiating the transaction
     * @param recipient Address receiving the tokens
     */
    function performAMLCheck(address sender, address recipient) external view returns (bool) {
        if (blacklisted[sender] || blacklisted[recipient]) {
            return false;
        }
        return true;
    }
    
    /**
     * @dev Add or remove address from blacklist (only owner)
     * @param account Address to blacklist/unblacklist
     * @param status True to blacklist, false to remove from blacklist
     */
    function updateBlacklist(address account, bool status) external onlyOwner {
        require(account != address(0), "SimpleAMLHook: Cannot blacklist zero address");
        blacklisted[account] = status;
        emit AddressBlacklisted(account, status);
    }
    
    /**
     * @dev Authorize or deauthorize token for conversion (only owner)
     * @param token Token address
     * @param status True to authorize, false to deauthorize
     */
    function updateAuthorizedToken(address token, bool status) external onlyOwner {
        require(token != address(0), "SimpleAMLHook: Invalid token address");
        authorizedTokens[token] = status;
        emit TokenAuthorized(token, status);
    }
    
    /**
     * @dev Update conversion rate for a token (only owner)
     * @param token Token address
     * @param rate Conversion rate (token per wINR, scaled by 1e18)
     */
    function updateConversionRate(address token, uint256 rate) external onlyOwner {
        require(token != address(0), "SimpleAMLHook: Invalid token address");
        require(rate > 0, "SimpleAMLHook: Invalid conversion rate");
        conversionRates[token] = rate;
        emit ConversionRateUpdated(token, rate);
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
     * @dev Check if a token is authorized for conversion
     * @param token Token address to check
     * @return True if authorized, false otherwise
     */
    function isAuthorizedToken(address token) external view returns (bool) {
        return authorizedTokens[token];
    }
    
    /**
     * @dev Get conversion rate for a token
     * @param token Token address
     * @return Conversion rate
     */
    function getConversionRate(address token) external view returns (uint256) {
        return conversionRates[token];
    }
}