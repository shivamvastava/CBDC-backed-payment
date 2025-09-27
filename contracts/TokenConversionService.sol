// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title TokenConversionService - Service for converting tokens to wINR
 * @dev This service handles the conversion of authorized tokens to wINR
 * @notice Designed for CBDC-backed payment systems with regulatory compliance
 */
contract TokenConversionService is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // wINR token address
    address public immutable wINR;
    
    // Mapping to track authorized tokens for conversion
    mapping(address => bool) public authorizedTokens;
    
    // Mapping to store conversion rates (token => rate per wINR, scaled by 1e18)
    mapping(address => uint256) public conversionRates;
    
    // Mapping to track minimum conversion amounts
    mapping(address => uint256) public minimumConversionAmounts;
    
    // Mapping to track maximum conversion amounts per transaction
    mapping(address => uint256) public maximumConversionAmounts;
    
    // Mapping to track daily conversion limits per user
    mapping(address => mapping(address => uint256)) public dailyConversionLimits;
    mapping(address => mapping(address => uint256)) public dailyConversionUsed;
    mapping(address => mapping(address => uint256)) public lastConversionDay;
    
    // Events
    event TokenAuthorized(address indexed token, bool status);
    event ConversionRateUpdated(address indexed token, uint256 rate);
    event MinimumConversionAmountUpdated(address indexed token, uint256 amount);
    event MaximumConversionAmountUpdated(address indexed token, uint256 amount);
    event TokensConverted(
        address indexed user,
        address indexed fromToken,
        uint256 fromAmount,
        uint256 wINRAmount,
        uint256 timestamp
    );
    event ConversionLimitUpdated(address indexed token, uint256 limit);
    
    // Modifier to check if token is authorized
    modifier onlyAuthorizedToken(address token) {
        require(authorizedTokens[token], "TokenConversionService: Token not authorized");
        _;
    }
    
    /**
     * @dev Constructor
     * @param _wINR wINR token address
     */
    constructor(address _wINR) {
        require(_wINR != address(0), "TokenConversionService: Invalid wINR address");
        wINR = _wINR;
    }
    
    /**
     * @dev Convert authorized token to wINR
     * @param token Token address to convert from
     * @param amount Amount of tokens to convert
     * @return wINRAmount Amount of wINR received
     */
    function convertToWINR(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyAuthorizedToken(token) returns (uint256 wINRAmount) {
        require(amount > 0, "TokenConversionService: Invalid amount");
        require(amount >= minimumConversionAmounts[token], "TokenConversionService: Amount below minimum");
        require(amount <= maximumConversionAmounts[token], "TokenConversionService: Amount exceeds maximum");
        
        // Check daily conversion limit
        _checkDailyLimit(msg.sender, token, amount);
        
        // Calculate wINR amount
        wINRAmount = (amount * conversionRates[token]) / 1e18;
        require(wINRAmount > 0, "TokenConversionService: Conversion results in zero wINR");
        
        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Transfer wINR to user
        IERC20(wINR).safeTransfer(msg.sender, wINRAmount);
        
        // Update daily conversion tracking
        _updateDailyConversion(msg.sender, token, amount);
        
        emit TokensConverted(msg.sender, token, amount, wINRAmount, block.timestamp);
        
        return wINRAmount;
    }
    
    /**
     * @dev Check daily conversion limit for a user
     * @param user User address
     * @param token Token address
     * @param amount Amount to convert
     */
    function _checkDailyLimit(address user, address token, uint256 amount) internal {
        uint256 currentDay = block.timestamp / 1 days;
        
        // Reset daily usage if it's a new day
        if (lastConversionDay[user][token] != currentDay) {
            dailyConversionUsed[user][token] = 0;
            lastConversionDay[user][token] = currentDay;
        }
        
        require(
            dailyConversionUsed[user][token] + amount <= dailyConversionLimits[user][token],
            "TokenConversionService: Daily conversion limit exceeded"
        );
    }
    
    /**
     * @dev Update daily conversion tracking
     * @param user User address
     * @param token Token address
     * @param amount Amount converted
     */
    function _updateDailyConversion(address user, address token, uint256 amount) internal {
        dailyConversionUsed[user][token] += amount;
    }
    
    /**
     * @dev Authorize or deauthorize token for conversion (only owner)
     * @param token Token address
     * @param status True to authorize, false to deauthorize
     */
    function updateAuthorizedToken(address token, bool status) external onlyOwner {
        require(token != address(0), "TokenConversionService: Invalid token address");
        authorizedTokens[token] = status;
        emit TokenAuthorized(token, status);
    }
    
    /**
     * @dev Update conversion rate for a token (only owner)
     * @param token Token address
     * @param rate Conversion rate (token per wINR, scaled by 1e18)
     */
    function updateConversionRate(address token, uint256 rate) external onlyOwner {
        require(token != address(0), "TokenConversionService: Invalid token address");
        require(rate > 0, "TokenConversionService: Invalid conversion rate");
        conversionRates[token] = rate;
        emit ConversionRateUpdated(token, rate);
    }
    
    /**
     * @dev Update minimum conversion amount for a token (only owner)
     * @param token Token address
     * @param amount Minimum amount
     */
    function updateMinimumConversionAmount(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "TokenConversionService: Invalid token address");
        minimumConversionAmounts[token] = amount;
        emit MinimumConversionAmountUpdated(token, amount);
    }
    
    /**
     * @dev Update maximum conversion amount for a token (only owner)
     * @param token Token address
     * @param amount Maximum amount
     */
    function updateMaximumConversionAmount(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "TokenConversionService: Invalid token address");
        maximumConversionAmounts[token] = amount;
        emit MaximumConversionAmountUpdated(token, amount);
    }
    
    /**
     * @dev Set daily conversion limit for a user and token (only owner)
     * @param user User address
     * @param token Token address
     * @param limit Daily limit
     */
    function setDailyConversionLimit(address user, address token, uint256 limit) external onlyOwner {
        require(user != address(0), "TokenConversionService: Invalid user address");
        require(token != address(0), "TokenConversionService: Invalid token address");
        dailyConversionLimits[user][token] = limit;
        emit ConversionLimitUpdated(token, limit);
    }
    
    /**
     * @dev Pause the conversion service (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the conversion service (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Get conversion quote
     * @param token Token address
     * @param amount Amount to convert
     * @return wINRAmount Amount of wINR that would be received
     */
    function getConversionQuote(address token, uint256 amount) external view returns (uint256 wINRAmount) {
        if (!authorizedTokens[token] || conversionRates[token] == 0) {
            return 0;
        }
        
        return (amount * conversionRates[token]) / 1e18;
    }
    
    /**
     * @dev Check if a token is authorized for conversion
     * @param token Token address
     * @return True if authorized, false otherwise
     */
    function isAuthorizedToken(address token) external view returns (bool) {
        return authorizedTokens[token];
    }
    
    /**
     * @dev Get remaining daily conversion limit for a user
     * @param user User address
     * @param token Token address
     * @return Remaining limit
     */
    function getRemainingDailyLimit(address user, address token) external view returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        
        if (lastConversionDay[user][token] != currentDay) {
            return dailyConversionLimits[user][token];
        }
        
        return dailyConversionLimits[user][token] - dailyConversionUsed[user][token];
    }
    
    /**
     * @dev Emergency function to withdraw stuck tokens (only owner)
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "TokenConversionService: Invalid token address");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
