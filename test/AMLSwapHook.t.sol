// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AMLSwapHook} from "../contracts/AMLSwapHook.sol";
import {WINR} from "../contracts/WINR.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

/**
 * @title AMLSwapHook Tests
 * @dev Comprehensive test suite for the AML Swap Hook contract
 */
contract AMLSwapHookTest is Test {
    AMLSwapHook public hook;
    WINR public winr;
    IPoolManager public poolManager;
    
    address public owner;
    address public user1;
    address public user2;
    address public blacklistedUser;
    address public authorizedToken;
    
    event AddressBlacklisted(address indexed account, bool status);
    event TokenAuthorized(address indexed token, bool status);
    event ConversionRateUpdated(address indexed token, uint256 rate);
    event SwapBlocked(address indexed user, string reason);
    event TokenConverted(address indexed user, address indexed fromToken, uint256 amount, uint256 wINRAmount);
    
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
    }
    
    function testInitialState() public {
        assertEq(hook.wINR(), address(winr));
        assertEq(hook.owner(), owner);
        assertFalse(hook.isBlacklisted(user1));
        assertFalse(hook.isAuthorizedToken(authorizedToken));
        assertEq(hook.getConversionRate(authorizedToken), 0);
    }
    
    function testGetHookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }
    
    function testUpdateBlacklist() public {
        vm.expectEmit(true, false, false, true);
        emit AddressBlacklisted(user1, true);
        
        hook.updateBlacklist(user1, true);
        
        assertTrue(hook.isBlacklisted(user1));
        
        vm.expectEmit(true, false, false, true);
        emit AddressBlacklisted(user1, false);
        
        hook.updateBlacklist(user1, false);
        
        assertFalse(hook.isBlacklisted(user1));
    }
    
    function testUpdateBlacklistZeroAddress() public {
        vm.expectRevert("AMLSwapHook: Cannot blacklist zero address");
        hook.updateBlacklist(address(0), true);
    }
    
    function testUpdateAuthorizedToken() public {
        vm.expectEmit(true, false, false, true);
        emit TokenAuthorized(authorizedToken, true);
        
        hook.updateAuthorizedToken(authorizedToken, true);
        
        assertTrue(hook.isAuthorizedToken(authorizedToken));
        
        vm.expectEmit(true, false, false, true);
        emit TokenAuthorized(authorizedToken, false);
        
        hook.updateAuthorizedToken(authorizedToken, false);
        
        assertFalse(hook.isAuthorizedToken(authorizedToken));
    }
    
    function testUpdateAuthorizedTokenZeroAddress() public {
        vm.expectRevert("AMLSwapHook: Invalid token address");
        hook.updateAuthorizedToken(address(0), true);
    }
    
    function testUpdateConversionRate() public {
        uint256 rate = 1e18; // 1:1 conversion rate
        
        vm.expectEmit(true, false, false, true);
        emit ConversionRateUpdated(authorizedToken, rate);
        
        hook.updateConversionRate(authorizedToken, rate);
        
        assertEq(hook.getConversionRate(authorizedToken), rate);
    }
    
    function testUpdateConversionRateZeroAddress() public {
        vm.expectRevert("AMLSwapHook: Invalid token address");
        hook.updateConversionRate(address(0), 1e18);
    }
    
    function testUpdateConversionRateZeroRate() public {
        vm.expectRevert("AMLSwapHook: Invalid conversion rate");
        hook.updateConversionRate(authorizedToken, 0);
    }
    
    function testOnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert();
        hook.updateBlacklist(user2, true);
        
        vm.prank(user1);
        vm.expectRevert();
        hook.updateAuthorizedToken(authorizedToken, true);
        
        vm.prank(user1);
        vm.expectRevert();
        hook.updateConversionRate(authorizedToken, 1e18);
        
        vm.prank(user1);
        vm.expectRevert();
        hook.emergencyWithdraw(authorizedToken, 1000);
    }
    
    function testEmergencyWithdraw() public {
        // This test would require setting up a scenario where tokens are stuck
        // For now, we'll just test that the function exists and has proper access control
        vm.expectRevert("AMLSwapHook: Invalid token address");
        hook.emergencyWithdraw(address(0), 1000);
    }
    
    function testFuzzUpdateBlacklist(address account, bool status) public {
        vm.assume(account != address(0));
        
        hook.updateBlacklist(account, status);
        assertEq(hook.isBlacklisted(account), status);
    }
    
    function testFuzzUpdateAuthorizedToken(address token, bool status) public {
        vm.assume(token != address(0));
        
        hook.updateAuthorizedToken(token, status);
        assertEq(hook.isAuthorizedToken(token), status);
    }
    
    function testFuzzUpdateConversionRate(address token, uint256 rate) public {
        vm.assume(token != address(0));
        vm.assume(rate > 0);
        
        hook.updateConversionRate(token, rate);
        assertEq(hook.getConversionRate(token), rate);
    }
    
    // Note: Testing the actual beforeSwap hook would require a more complex setup
    // with a real PoolManager and proper pool initialization
    // This would typically be done in integration tests
}
