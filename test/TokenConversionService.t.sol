// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TokenConversionService } from "../contracts/TokenConversionService.sol";
import { WINR } from "../contracts/WINR.sol";

/**
 * @title TokenConversionService Tests
 * @dev Comprehensive test suite for the Token Conversion Service contract
 */
contract TokenConversionServiceTest is Test {
    TokenConversionService public conversionService;
    WINR public winr;

    address public owner;
    address public user1;
    address public user2;
    address public authorizedToken;

    event TokenAuthorized(address indexed token, bool status);
    event ConversionRateUpdated(address indexed token, uint256 rate);
    event MinimumConversionAmountUpdated(address indexed token, uint256 amount);
    event MaximumConversionAmountUpdated(address indexed token, uint256 amount);
    event TokensConverted(
        address indexed user, address indexed fromToken, uint256 fromAmount, uint256 wInrAmount, uint256 timestamp
    );
    event ConversionLimitUpdated(address indexed token, uint256 limit);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        authorizedToken = makeAddr("authorizedToken");

        // Deploy WINR token
        winr = new WINR(100_000_000 * 10 ** 18);

        // Deploy Token Conversion Service
        conversionService = new TokenConversionService(address(winr));

        // Transfer some WINR to the conversion service for testing
        assertTrue(winr.transfer(address(conversionService), 10_000_000 * 10 ** 18));
    }

    function testInitialState() public view {
        assertEq(conversionService.wINR(), address(winr));
        assertEq(conversionService.owner(), owner);
        assertFalse(conversionService.isAuthorizedToken(authorizedToken));
        assertEq(conversionService.getConversionRate(authorizedToken), 0);
    }

    function testUpdateAuthorizedToken() public {
        vm.expectEmit(true, false, false, true);
        emit TokenAuthorized(authorizedToken, true);

        conversionService.updateAuthorizedToken(authorizedToken, true);

        assertTrue(conversionService.isAuthorizedToken(authorizedToken));

        vm.expectEmit(true, false, false, true);
        emit TokenAuthorized(authorizedToken, false);

        conversionService.updateAuthorizedToken(authorizedToken, false);

        assertFalse(conversionService.isAuthorizedToken(authorizedToken));
    }

    function testUpdateAuthorizedTokenZeroAddress() public {
        vm.expectRevert("TokenConversionService: Invalid token address");
        conversionService.updateAuthorizedToken(address(0), true);
    }

    function testUpdateConversionRate() public {
        uint256 rate = 1e18; // 1:1 conversion rate

        vm.expectEmit(true, false, false, true);
        emit ConversionRateUpdated(authorizedToken, rate);

        conversionService.updateConversionRate(authorizedToken, rate);

        assertEq(conversionService.getConversionRate(authorizedToken), rate);
    }

    function testUpdateConversionRateZeroAddress() public {
        vm.expectRevert("TokenConversionService: Invalid token address");
        conversionService.updateConversionRate(address(0), 1e18);
    }

    function testUpdateConversionRateZeroRate() public {
        vm.expectRevert("TokenConversionService: Invalid conversion rate");
        conversionService.updateConversionRate(authorizedToken, 0);
    }

    function testUpdateMinimumConversionAmount() public {
        uint256 minAmount = 1000;

        vm.expectEmit(true, false, false, true);
        emit MinimumConversionAmountUpdated(authorizedToken, minAmount);

        conversionService.updateMinimumConversionAmount(authorizedToken, minAmount);
    }

    function testUpdateMaximumConversionAmount() public {
        uint256 maxAmount = 1000000;

        vm.expectEmit(true, false, false, true);
        emit MaximumConversionAmountUpdated(authorizedToken, maxAmount);

        conversionService.updateMaximumConversionAmount(authorizedToken, maxAmount);
    }

    function testSetDailyConversionLimit() public {
        uint256 limit = 10000;

        vm.expectEmit(true, false, false, true);
        emit ConversionLimitUpdated(authorizedToken, limit);

        conversionService.setDailyConversionLimit(user1, authorizedToken, limit);
    }

    function testGetConversionQuote() public {
        // Test with unauthorized token
        assertEq(conversionService.getConversionQuote(authorizedToken, 1000), 0);

        // Authorize token and set rate
        conversionService.updateAuthorizedToken(authorizedToken, true);
        conversionService.updateConversionRate(authorizedToken, 1e18);

        // Test conversion quote
        assertEq(conversionService.getConversionQuote(authorizedToken, 1000), 1000);
    }

    function testGetRemainingDailyLimit() public {
        uint256 limit = 10000;
        conversionService.setDailyConversionLimit(user1, authorizedToken, limit);

        assertEq(conversionService.getRemainingDailyLimit(user1, authorizedToken), limit);
    }

    function testPauseAndUnpause() public {
        conversionService.pause();
        assertTrue(conversionService.paused());

        conversionService.unpause();
        assertFalse(conversionService.paused());
    }

    function testOnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert();
        conversionService.updateAuthorizedToken(authorizedToken, true);

        vm.prank(user1);
        vm.expectRevert();
        conversionService.updateConversionRate(authorizedToken, 1e18);

        vm.prank(user1);
        vm.expectRevert();
        conversionService.updateMinimumConversionAmount(authorizedToken, 1000);

        vm.prank(user1);
        vm.expectRevert();
        conversionService.updateMaximumConversionAmount(authorizedToken, 1000000);

        vm.prank(user1);
        vm.expectRevert();
        conversionService.setDailyConversionLimit(user2, authorizedToken, 10000);

        vm.prank(user1);
        vm.expectRevert();
        conversionService.pause();

        vm.prank(user1);
        vm.expectRevert();
        conversionService.unpause();

        vm.prank(user1);
        vm.expectRevert();
        conversionService.emergencyWithdraw(authorizedToken, 1000);
    }

    function testEmergencyWithdraw() public {
        vm.expectRevert("TokenConversionService: Invalid token address");
        conversionService.emergencyWithdraw(address(0), 1000);
    }

    function testFuzzUpdateAuthorizedToken(address token, bool status) public {
        vm.assume(token != address(0));

        conversionService.updateAuthorizedToken(token, status);
        assertEq(conversionService.isAuthorizedToken(token), status);
    }

    function testFuzzUpdateConversionRate(address token, uint256 rate) public {
        vm.assume(token != address(0));
        vm.assume(rate > 0);

        conversionService.updateConversionRate(token, rate);
        assertEq(conversionService.getConversionRate(token), rate);
    }

    function testFuzzGetConversionQuote(address token, uint256 amount) public {
        vm.assume(token != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max); // Prevent overflow in conversion calculation

        // Test with unauthorized token
        assertEq(conversionService.getConversionQuote(token, amount), 0);

        // Authorize token and set rate
        conversionService.updateAuthorizedToken(token, true);
        conversionService.updateConversionRate(token, 1e18);

        // Test conversion quote
        assertEq(conversionService.getConversionQuote(token, amount), amount);
    }

    function testFuzzSetDailyConversionLimit(address user, address token, uint256 limit) public {
        vm.assume(user != address(0));
        vm.assume(token != address(0));

        conversionService.setDailyConversionLimit(user, token, limit);
        assertEq(conversionService.getRemainingDailyLimit(user, token), limit);
    }
}
