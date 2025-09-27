// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {AMLSwapHook} from "./AMLSwapHook.sol";
import {WINR} from "./WINR.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PoolFactory - Factory for creating wINR/ETH pools with AML hooks
 * @dev This factory creates Uniswap V4 pools with integrated AML compliance hooks
 * @notice Designed for CBDC-backed payment systems
 */
contract PoolFactory is Ownable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    
    // Uniswap V4 PoolManager
    IPoolManager public immutable poolManager;
    
    // wINR token address
    address public immutable wINR;
    
    // ETH address (native token)
    address public constant ETH = address(0);
    
    // Mapping to track created pools
    mapping(PoolId => bool) public pools;
    
    // Events
    event PoolCreated(
        PoolId indexed poolId,
        address indexed hook,
        uint24 fee,
        int24 tickSpacing
    );
    event HookUpdated(PoolId indexed poolId, address indexed newHook);
    
    /**
     * @dev Constructor
     * @param _poolManager Uniswap V4 PoolManager address
     * @param _wINR wINR token address
     */
    constructor(IPoolManager _poolManager, address _wINR) {
        require(address(_poolManager) != address(0), "PoolFactory: Invalid PoolManager");
        require(_wINR != address(0), "PoolFactory: Invalid wINR address");
        
        poolManager = _poolManager;
        wINR = _wINR;
    }
    
    /**
     * @dev Create a new wINR/ETH pool with AML hook
     * @param fee Pool fee (in hundredths of a bip, e.g., 3000 = 0.3%)
     * @param tickSpacing Tick spacing for the pool
     * @param initialSqrtPriceX96 Initial sqrt price for the pool
     * @return poolId The created pool ID
     * @return hook The deployed AML hook address
     */
    function createPool(
        uint24 fee,
        int24 tickSpacing,
        uint160 initialSqrtPriceX96
    ) external onlyOwner returns (PoolId poolId, address hook) {
        // Deploy AML hook
        hook = address(new AMLSwapHook(poolManager, wINR));
        
        // Create pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(wINR),
            currency1: Currency.wrap(ETH),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: AMLSwapHook(hook)
        });
        
        // Get pool ID
        poolId = key.toId();
        
        // Initialize the pool
        poolManager.initialize(key, initialSqrtPriceX96);
        
        // Mark pool as created
        pools[poolId] = true;
        
        emit PoolCreated(poolId, hook, fee, tickSpacing);
        
        return (poolId, hook);
    }
    
    /**
     * @dev Create multiple pools with different fee tiers
     * @param fees Array of fee values
     * @param tickSpacings Array of tick spacing values
     * @param initialSqrtPriceX96 Initial sqrt price for all pools
     * @return poolIds Array of created pool IDs
     * @return hooks Array of deployed hook addresses
     */
    function createMultiplePools(
        uint24[] calldata fees,
        int24[] calldata tickSpacings,
        uint160 initialSqrtPriceX96
    ) external onlyOwner returns (PoolId[] memory poolIds, address[] memory hooks) {
        require(fees.length == tickSpacings.length, "PoolFactory: Array length mismatch");
        require(fees.length > 0, "PoolFactory: Empty arrays");
        
        poolIds = new PoolId[](fees.length);
        hooks = new address[](fees.length);
        
        for (uint256 i = 0; i < fees.length; i++) {
            (poolIds[i], hooks[i]) = createPool(fees[i], tickSpacings[i], initialSqrtPriceX96);
        }
        
        return (poolIds, hooks);
    }
    
    /**
     * @dev Check if a pool exists
     * @param poolId Pool ID to check
     * @return True if pool exists, false otherwise
     */
    function poolExists(PoolId poolId) external view returns (bool) {
        return pools[poolId];
    }
    
    /**
     * @dev Get pool key for a given pool ID
     * @param poolId Pool ID
     * @return Pool key
     */
    function getPoolKey(PoolId poolId) external pure returns (PoolKey memory) {
        // This is a simplified version - in production, you'd store and retrieve
        // the actual pool key from storage
        revert("PoolFactory: Pool key retrieval not implemented");
    }
    
    /**
     * @dev Emergency function to pause pool creation (only owner)
     */
    function pausePoolCreation() external onlyOwner {
        // Implementation would depend on your specific requirements
        revert("PoolFactory: Pause functionality not implemented");
    }
    
    /**
     * @dev Emergency function to resume pool creation (only owner)
     */
    function resumePoolCreation() external onlyOwner {
        // Implementation would depend on your specific requirements
        revert("PoolFactory: Resume functionality not implemented");
    }
}
