// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { WINR } from "../contracts/WINR.sol";
import { SimpleAMLHook } from "../contracts/SimpleAMLHook.sol";
import { TokenConversionService } from "../contracts/TokenConversionService.sol";
import { SimplePoolFactory } from "../contracts/SimplePoolFactory.sol";

/**
 * @title Simplified Integration Tests
 * @dev End-to-end integration tests for the CBDC payment system core functionality
 */
contract SimpleIntegrationTest is Test {
    WINR public winr;
    SimpleAMLHook public hook;
    TokenConversionService public conversionService;
    SimplePoolFactory public poolFactory;

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
        winr = new WINR(100_000_000 * 10 ** 18);

        // Deploy Simple AML Hook
        hook = new SimpleAMLHook(address(winr));

        // Deploy Token Conversion Service
        conversionService = new TokenConversionService(address(winr));

        // Deploy Simple Pool Factory
        poolFactory = new SimplePoolFactory(address(winr));

        // Transfer some WINR to the conversion service for testing
        assertTrue(winr.transfer(address(conversionService), 10_000_000 * 10 ** 18));
    }

    function testCompleteSystemSetup() public view {
        // Test that all contracts are deployed correctly
        assertEq(hook.wINR(), address(winr));
        assertEq(conversionService.wINR(), address(winr));
        assertEq(poolFactory.wINR(), address(winr));

        // Test initial states
        assertFalse(hook.isBlacklisted(user1));
        assertFalse(conversionService.isAuthorizedToken(authorizedToken));
        assertEq(poolFactory.getTotalPools(), 0);
    }

    function testAMLComplianceFlow() public {
        // Test AML check with clean addresses
        assertTrue(hook.performAmlCheck(user1, user2));

        // Add user to blacklist
        hook.updateBlacklist(blacklistedUser, true);
        assertTrue(hook.isBlacklisted(blacklistedUser));

        // Test AML check with blacklisted sender
        assertFalse(hook.performAmlCheck(blacklistedUser, user2));

        // Test AML check with blacklisted recipient
        assertFalse(hook.performAmlCheck(user1, blacklistedUser));

        // Remove user from blacklist
        hook.updateBlacklist(blacklistedUser, false);
        assertFalse(hook.isBlacklisted(blacklistedUser));

        // Test AML check after removal
        assertTrue(hook.performAmlCheck(blacklistedUser, user2));
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
        // Test initial state
        assertEq(poolFactory.getTotalPools(), 0);

        // Create a pool
        uint256 poolId = poolFactory.createPool(authorizedToken, 3000, address(hook));

        // Verify pool creation
        assertEq(poolFactory.getTotalPools(), 1);
        assertTrue(poolFactory.poolExists(poolId));

        // Get pool info
        SimplePoolFactory.PoolInfo memory poolInfo = poolFactory.getPool(poolId);
        assertEq(poolInfo.token0, address(winr));
        assertEq(poolInfo.token1, authorizedToken);
        assertEq(poolInfo.fee, 3000);
        assertEq(poolInfo.hook, address(hook));
        assertTrue(poolInfo.active);
    }

    function testSystemPauseAndResume() public {
        // Test WINR token pause
        winr.pause();
        assertTrue(winr.paused());

        vm.expectRevert("WINR: Token transfers are paused");
        (bool successPause,) =
            address(winr).call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), user1, 1000));
        assertFalse(successPause);

        winr.unpause();
        assertFalse(winr.paused());

        // Test conversion service pause
        conversionService.pause();
        assertTrue(conversionService.paused());

        conversionService.unpause();
        assertFalse(conversionService.paused());

        // Test pool factory pause
        poolFactory.pausePoolCreation();
        assertTrue(poolFactory.paused());

        poolFactory.resumePoolCreation();
        assertFalse(poolFactory.paused());
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

        vm.prank(user1);
        vm.expectRevert();
        poolFactory.createPool(authorizedToken, 3000, address(hook));
    }

    function testWINRTokenBasicFunctionality() public {
        // Test minting
        uint256 initialBalance = winr.balanceOf(user1);
        winr.mint(user1, 1000);
        assertEq(winr.balanceOf(user1), initialBalance + 1000);

        // Test burning
        vm.prank(user1);
        winr.burn(500);
        assertEq(winr.balanceOf(user1), initialBalance + 500);

        // Test blacklisting prevents transfers
        winr.updateBlacklist(user1, true);
        assertTrue(winr.isBlacklisted(user1));

        vm.prank(user1);
        vm.expectRevert("WINR: Sender is blacklisted");
        (bool successBlk,) =
            address(winr).call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), user2, 100));
        assertFalse(successBlk);

        // Remove from blacklist
        winr.updateBlacklist(user1, false);
        assertFalse(winr.isBlacklisted(user1));

        // Transfer should work now
        vm.prank(user1);
        assertTrue(winr.transfer(user2, 100));
        assertEq(winr.balanceOf(user2), 100);
    }

    function testHookAndConversionServiceIntegration() public {
        // Set up both hook and conversion service
        hook.updateAuthorizedToken(authorizedToken, true);
        hook.updateConversionRate(authorizedToken, 1e18);

        conversionService.updateAuthorizedToken(authorizedToken, true);
        conversionService.updateConversionRate(authorizedToken, 1e18);

        // Verify both have the same configuration
        assertTrue(hook.isAuthorizedToken(authorizedToken));
        assertTrue(conversionService.isAuthorizedToken(authorizedToken));
        assertEq(hook.getConversionRate(authorizedToken), conversionService.getConversionRate(authorizedToken));
    }

    function testPoolFactoryWithMultiplePools() public {
        address token2 = makeAddr("token2");
        address token3 = makeAddr("token3");

        // Create multiple pools
        uint256 pool1 = poolFactory.createPool(authorizedToken, 3000, address(hook));
        uint256 pool2 = poolFactory.createPool(token2, 500, address(hook));
        uint256 pool3 = poolFactory.createPool(token3, 10000, address(hook));

        // Verify all pools exist
        assertEq(poolFactory.getTotalPools(), 3);
        assertTrue(poolFactory.poolExists(pool1));
        assertTrue(poolFactory.poolExists(pool2));
        assertTrue(poolFactory.poolExists(pool3));

        // Deactivate a pool
        poolFactory.deactivatePool(pool2);
        assertFalse(poolFactory.poolExists(pool2));

        // Other pools should still exist
        assertTrue(poolFactory.poolExists(pool1));
        assertTrue(poolFactory.poolExists(pool3));
    }
}
