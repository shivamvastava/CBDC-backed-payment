// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {WINR} from "../contracts/WINR.sol";
import {AMLSwapHook} from "../contracts/AMLSwapHook.sol";
import {TokenConversionService} from "../contracts/TokenConversionService.sol";
import {PoolFactory} from "../contracts/PoolFactory.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";

/**
 * @title Integration Tests
 * @dev End-to-end integration tests for the CBDC payment system
 */
contract IntegrationTest is Test {
    WINR public winr;
    AMLSwapHook public hook;
    TokenConversionService public conversionService;
    PoolFactory public poolFactory;
    IPoolManager public poolManager;
    
    address public owner;
    address public user1;
    address public user2;
    address public blacklistedUser;
    address public authorizedToken;
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        blacklistedUser = makeAddr("blacklistedUser");
        authorizedToken = makeAddr("authorizedToken");
        
        // Deploy WINR token
        winr = new WINR(100_000_000 * 10**18);
        
        // Mock PoolManager (in real tests, you'd use the actual PoolManager)
        poolManager = IPoolManager(makeAddr("poolManager"));
        
        // Deploy AML Hook
        hook = new AMLSwapHook(poolManager, address(winr));
        
        // Deploy Token Conversion Service
        conversionService = new TokenConversionService(address(winr));
        
        // Deploy Pool Factory
        poolFactory = new PoolFactory(poolManager, address(winr));
        
        // Transfer some WINR to the conversion service for testing
        winr.transfer(address(conversionService), 10_000_000 * 10**18);
    }
    
    function testCompleteSystemSetup() public {
        // Test that all contracts are deployed correctly
        assertEq(hook.wINR(), address(winr));
        assertEq(conversionService.wINR(), address(winr));
        assertEq(poolFactory.wINR(), address(winr));
        
        // Test initial states
        assertFalse(hook.isBlacklisted(user1));
        assertFalse(conversionService.isAuthorizedToken(authorizedToken));
    }
    
    function testAMLComplianceFlow() public {
        // Add user to blacklist
        hook.updateBlacklist(blacklistedUser, true);
        assertTrue(hook.isBlacklisted(blacklistedUser));
        
        // Remove user from blacklist
        hook.updateBlacklist(blacklistedUser, false);
        assertFalse(hook.isBlacklisted(blacklistedUser));
    }
    
    function testTokenConversionFlow() public {
        // Authorize token for conversion
        conversionService.updateAuthorizedToken(authorizedToken, true);
        assertTrue(conversionService.isAuthorizedToken(authorizedToken));
        
        // Set conversion rate (1:1 for simplicity)
        conversionService.updateConversionRate(authorizedToken, 1e18);
        assertEq(conversionService.getConversionRate(authorizedToken), 1e18);
        
        // Set minimum and maximum conversion amounts
        conversionService.updateMinimumConversionAmount(authorizedToken, 1000);
        conversionService.updateMaximumConversionAmount(authorizedToken, 1000000);
        
        // Set daily conversion limit
        conversionService.setDailyConversionLimit(user1, authorizedToken, 10000);
        assertEq(conversionService.getRemainingDailyLimit(user1, authorizedToken), 10000);
        
        // Test conversion quote
        assertEq(conversionService.getConversionQuote(authorizedToken, 1000), 1000);
    }
    
    function testPoolCreationFlow() public {
        // Test pool creation (this would require a real PoolManager in production)
        // For now, we'll test that the factory is set up correctly
        assertEq(poolFactory.wINR(), address(winr));
        assertEq(address(poolFactory.poolManager()), address(poolManager));
    }
    
    function testSystemPauseAndResume() public {
        // Test WINR token pause
        winr.pause();
        assertTrue(winr.paused());
        
        vm.expectRevert("WINR: Token transfers are paused");
        winr.transfer(user1, 1000);
        
        winr.unpause();
        assertFalse(winr.paused());
        
        // Test conversion service pause
        conversionService.pause();
        assertTrue(conversionService.paused());
        
        conversionService.unpause();
        assertFalse(conversionService.paused());
    }
    
    function testAccessControl() public {
        // Test that only owner can perform administrative functions
        vm.prank(user1);
        vm.expectRevert();
        winr.mint(user2, 1000);
        
        vm.prank(user1);
        vm.expectRevert();
        hook.updateBlacklist(user2, true);
        
        vm.prank(user1);
        vm.expectRevert();
        conversionService.updateAuthorizedToken(authorizedToken, true);
    }
    
    function testEmergencyFunctions() public {
        // Test emergency withdraw functions
        vm.expectRevert("AMLSwapHook: Invalid token address");
        hook.emergencyWithdraw(address(0), 1000);
        
        vm.expectRevert("TokenConversionService: Invalid token address");
        conversionService.emergencyWithdraw(address(0), 1000);
    }
    
    function testFuzzSystemIntegration(address user, address token, uint256 amount) public {
        vm.assume(user != address(0));
        vm.assume(token != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 1000000);
        
        // Test blacklist functionality
        hook.updateBlacklist(user, true);
        assertTrue(hook.isBlacklisted(user));
        
        hook.updateBlacklist(user, false);
        assertFalse(hook.isBlacklisted(user));
        
        // Test token authorization
        conversionService.updateAuthorizedToken(token, true);
        assertTrue(conversionService.isAuthorizedToken(token));
        
        // Test conversion rate
        conversionService.updateConversionRate(token, 1e18);
        assertEq(conversionService.getConversionRate(token), 1e18);
        
        // Test conversion quote
        assertEq(conversionService.getConversionQuote(token, amount), amount);
    }
    
    function testGasOptimization() public {
        // Test gas usage for common operations
        uint256 gasStart = gasleft();
        
        // Blacklist operation
        hook.updateBlacklist(user1, true);
        uint256 gasAfterBlacklist = gasleft();
        
        // Token authorization
        conversionService.updateAuthorizedToken(authorizedToken, true);
        uint256 gasAfterAuth = gasleft();
        
        // Conversion rate update
        conversionService.updateConversionRate(authorizedToken, 1e18);
        uint256 gasAfterRate = gasleft();
        
        // Log gas usage
        console.log("Gas used for blacklist:", gasStart - gasAfterBlacklist);
        console.log("Gas used for authorization:", gasAfterBlacklist - gasAfterAuth);
        console.log("Gas used for rate update:", gasAfterAuth - gasAfterRate);
        
        // Ensure operations are gas efficient
        assertLt(gasStart - gasAfterRate, 200000); // Should use less than 200k gas
    }
}
