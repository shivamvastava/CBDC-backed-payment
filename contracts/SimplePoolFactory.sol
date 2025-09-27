// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SimplePoolFactory - Simplified pool factory without Uniswap V4 dependencies
 * @dev Basic pool management functionality for CBDC systems
 */
contract SimplePoolFactory is Ownable, Pausable {
    // wINR token address
    address public immutable wINR;
    
    // Pool counter
    uint256 public poolCount;
    
    // Mapping to track created pools
    mapping(uint256 => PoolInfo) public pools;
    
    struct PoolInfo {
        address token0;
        address token1;
        uint24 fee;
        address hook;
        bool active;
    }
    
    // Events
    event PoolCreated(
        uint256 indexed poolId,
        address indexed token0,
        address indexed token1,
        uint24 fee,
        address hook
    );
    
    /**
     * @dev Constructor
     * @param _wINR wINR token address
     */
    constructor(address _wINR) Ownable(msg.sender) {
        require(_wINR != address(0), "SimplePoolFactory: Invalid wINR address");
        wINR = _wINR;
    }
    
    /**
     * @dev Create a new pool
     * @param token1 Second token address (first is always wINR)
     * @param fee Pool fee
     * @param hook Hook address
     * @return poolId The created pool ID
     */
    function createPool(
        address token1,
        uint24 fee,
        address hook
    ) external onlyOwner whenNotPaused returns (uint256 poolId) {
        require(token1 != address(0), "SimplePoolFactory: Invalid token address");
        require(token1 != wINR, "SimplePoolFactory: Cannot create wINR/wINR pool");
        
        poolId = poolCount++;
        
        pools[poolId] = PoolInfo({
            token0: wINR,
            token1: token1,
            fee: fee,
            hook: hook,
            active: true
        });
        
        emit PoolCreated(poolId, wINR, token1, fee, hook);
        
        return poolId;
    }
    
    /**
     * @dev Check if a pool exists
     * @param poolId Pool ID to check
     * @return True if pool exists and is active
     */
    function poolExists(uint256 poolId) external view returns (bool) {
        return poolId < poolCount && pools[poolId].active;
    }
    
    /**
     * @dev Get pool information
     * @param poolId Pool ID
     * @return Pool information
     */
    function getPool(uint256 poolId) external view returns (PoolInfo memory) {
        require(poolId < poolCount, "SimplePoolFactory: Pool does not exist");
        return pools[poolId];
    }
    
    /**
     * @dev Get total number of pools
     * @return Total number of pools created
     */
    function getTotalPools() external view returns (uint256) {
        return poolCount;
    }
    
    /**
     * @dev Deactivate a pool (only owner)
     * @param poolId Pool ID to deactivate
     */
    function deactivatePool(uint256 poolId) external onlyOwner {
        require(poolId < poolCount, "SimplePoolFactory: Pool does not exist");
        pools[poolId].active = false;
    }
    
    /**
     * @dev Emergency function to pause pool creation (only owner)
     */
    function pausePoolCreation() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Emergency function to resume pool creation (only owner)
     */
    function resumePoolCreation() external onlyOwner {
        _unpause();
    }
}