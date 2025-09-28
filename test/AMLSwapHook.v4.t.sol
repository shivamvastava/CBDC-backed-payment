/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { SwapParams } from "v4-core/src/types/PoolOperation.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency, CurrencyLibrary } from "v4-core/src/types/Currency.sol";

import { AMLSwapHook } from "../contracts/AMLSwapHook.sol";
import { WINR } from "../contracts/WINR.sol";

contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 supply) ERC20(name_, symbol_) {
        _mint(msg.sender, supply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMLSwapHookV4Test is Test {
    using CurrencyLibrary for Currency;

    // Contracts under test
    AMLSwapHook public hook;
    WINR public winr;
    TestToken public tokenIn; // authorized foreign token for conversion example

    // Addresses
    address public poolManager = address(0x0000000000000000000000000000000000000FEE); // placeholder non-zero
    address public owner;
    address public userApproved;
    address public userBlacklisted;

    // Constants
    uint256 public constant INITIAL_WINR_SUPPLY = 100_000_000e18;
    uint256 public constant HOOK_WINR_SEED = 1_000_000e18;

    function setUp() public {
        owner = address(this);
        userApproved = vm.addr(0xA11CE);
        userBlacklisted = vm.addr(0xBAD);

        // Deploy WINR and seed initial balances
        winr = new WINR(INITIAL_WINR_SUPPLY);

        // Deploy hook with mock PoolManager (non-zero address) and wINR
        hook = new AMLSwapHook(IPoolManager(poolManager), address(winr));

        // Seed hook with some wINR so it can pay out conversions
        winr.transfer(address(hook), HOOK_WINR_SEED);

        // Deploy a simple ERC20 to act as an authorized token for conversion
        tokenIn = new TestToken("TestIn", "TIN", 0);
        // Mint some to userApproved for conversion tests
        tokenIn.mint(userApproved, 1_000_000e18);
    }

    // -------------------------------
    // Blacklist behavior
    // -------------------------------

    function testBlacklistSenderBlocksBeforeSwap() public {
        // Blacklist the sender
        hook.updateBlacklist(userBlacklisted, true);

        // Build a dummy PoolKey; currencies are irrelevant for blacklist test
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(winr)),
            currency1: Currency.wrap(address(tokenIn)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(1e18), sqrtPriceLimitX96: uint160(1) << 96 });

        // Expect revert on blacklisted sender
        vm.expectRevert(bytes("AMLSwapHook: Sender is blacklisted"));
        vm.prank(poolManager);
        hook.beforeSwap(userBlacklisted, key, params, bytes(""));
    }

    function testBlacklistRecipientBlocksBeforeSwap() public {
        // Blacklist the recipient
        hook.updateBlacklist(userBlacklisted, true);

        // Build a dummy PoolKey; currencies are irrelevant for blacklist test
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(winr)),
            currency1: Currency.wrap(address(tokenIn)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(1e18), sqrtPriceLimitX96: uint160(1) << 96 });

        // Provide recipient in hookData (abi.encode(address))
        bytes memory hookData = abi.encode(userBlacklisted);

        // Expect revert on blacklisted recipient
        vm.expectRevert(bytes("AMLSwapHook: Recipient is blacklisted"));
        vm.prank(poolManager);
        hook.beforeSwap(userApproved, key, params, hookData);
    }

    function testUpdateBlacklistZeroAddressReverts() public {
        vm.expectRevert(bytes("AMLSwapHook: Cannot blacklist zero address"));
        hook.updateBlacklist(address(0), true);
    }

    // -------------------------------
    // Configuration paths
    // -------------------------------

    function testAuthorizeTokenAndSetConversionRate() public {
        address token = address(tokenIn);
        assertFalse(hook.isAuthorizedToken(token));
        assertEq(hook.getConversionRate(token), 0);

        // Authorize and set rate
        hook.updateAuthorizedToken(token, true);
        hook.updateConversionRate(token, 1e18);

        assertTrue(hook.isAuthorizedToken(token));
        assertEq(hook.getConversionRate(token), 1e18);
    }

    function testUpdateAuthorizedTokenZeroAddressReverts() public {
        vm.expectRevert(bytes("AMLSwapHook: Invalid token address"));
        hook.updateAuthorizedToken(address(0), true);
    }

    function testUpdateConversionRateZeroAddressReverts() public {
        vm.expectRevert(bytes("AMLSwapHook: Invalid token address"));
        hook.updateConversionRate(address(0), 1e18);
    }

    function testUpdateConversionRateZeroRateReverts() public {
        vm.expectRevert(bytes("AMLSwapHook: Invalid conversion rate"));
        hook.updateConversionRate(address(tokenIn), 0);
    }

    // -------------------------------
    // Conversion path via beforeSwap
    // -------------------------------

    function testBeforeSwapTriggersConversionWhenAuthorized() public {
        // Arrange: authorize tokenIn and set 1:1 conversion rate to wINR
        hook.updateAuthorizedToken(address(tokenIn), true);
        hook.updateConversionRate(address(tokenIn), 1e18);

        // Ensure user has tokenIn and approved the hook to pull funds
        uint256 fromAmount = 500e18;
        vm.startPrank(userApproved);
        tokenIn.approve(address(hook), fromAmount);
        vm.stopPrank();

        // PoolKey: tokenIn as currency0, wINR as currency1; zeroForOne=true means tokenIn is input
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(tokenIn)),
            currency1: Currency.wrap(address(winr)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        // amountSpecified > 0 (exact input)
        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(fromAmount), sqrtPriceLimitX96: uint160(1) << 96 });

        // Record balances
        uint256 userTokenInBefore = tokenIn.balanceOf(userApproved);
        uint256 userWINRBefore = winr.balanceOf(userApproved);
        uint256 hookWINRBefore = winr.balanceOf(address(hook));

        // Act
        // The hook's external beforeSwap in BaseHook is only callable by PoolManager; simulate that sender.
        vm.prank(poolManager);
        hook.beforeSwap(userApproved, key, params, bytes(""));

        // 1:1 conversion expected
        uint256 expectedWINR = fromAmount;

        // Assert: tokenIn pulled from user
        assertEq(tokenIn.balanceOf(userApproved), userTokenInBefore - fromAmount, "user tokenIn should decrease");

        // Assert: user received wINR, hook paid out wINR
        assertEq(winr.balanceOf(userApproved), userWINRBefore + expectedWINR, "user wINR should increase");
        assertEq(winr.balanceOf(address(hook)), hookWINRBefore - expectedWINR, "hook wINR should decrease");
    }

    // -------------------------------
    // Additional negative tests
    // -------------------------------

    function testBeforeSwapRevertsWhenRateUnset() public {
        // Authorize tokenIn but do not set conversion rate
        hook.updateAuthorizedToken(address(tokenIn), true);

        // Approve the hook to pull user tokens
        uint256 fromAmount = 100e18;
        vm.startPrank(userApproved);
        tokenIn.approve(address(hook), fromAmount);
        vm.stopPrank();

        // Build PoolKey with tokenIn as input (zeroForOne = true)
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(tokenIn)),
            currency1: Currency.wrap(address(winr)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(fromAmount), sqrtPriceLimitX96: uint160(1) << 96 });

        // Expect revert due to missing conversion rate
        vm.expectRevert(bytes("AMLSwapHook: No conversion rate set"));
        vm.prank(poolManager);
        hook.beforeSwap(userApproved, key, params, bytes(""));
    }

    function testNoConversionWhenTokenInIsWINR() public {
        // Authorize tokenIn and set rate, but we will set tokenIn == wINR
        hook.updateAuthorizedToken(address(winr), true);
        hook.updateConversionRate(address(winr), 1e18);

        uint256 fromAmount = 50e18;

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(winr)), // tokenIn == wINR
            currency1: Currency.wrap(address(tokenIn)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(fromAmount), sqrtPriceLimitX96: uint160(1) << 96 });

        uint256 userWINRBefore = winr.balanceOf(userApproved);
        uint256 hookWINRBefore = winr.balanceOf(address(hook));

        // No approvals needed for conversion path since conversion should NOT trigger
        vm.prank(poolManager);
        hook.beforeSwap(userApproved, key, params, bytes(""));

        // No conversion should occur
        assertEq(winr.balanceOf(userApproved), userWINRBefore, "user wINR should be unchanged");
        assertEq(winr.balanceOf(address(hook)), hookWINRBefore, "hook wINR should be unchanged");
    }

    function testOnlyPoolManagerGuardIsEnforced() public {
        // Build a minimal key/params; call from non-poolManager should revert
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(winr)),
            currency1: Currency.wrap(address(tokenIn)),
            fee: 3000,
            tickSpacing: 60,
            hooks: AMLSwapHook(address(0))
        });

        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: int256(1e18), sqrtPriceLimitX96: uint160(1) << 96 });

        // Expect custom error NotPoolManager()
        vm.expectRevert(bytes4(keccak256("NotPoolManager()")));
        // Intentionally NOT using vm.prank(poolManager) to simulate unauthorized caller
        hook.beforeSwap(userApproved, key, params, bytes(""));
    }

    function testEmergencyWithdrawOnlyOwnerAndSuccess() public {
        // Non-owner attempt should revert
        vm.prank(userApproved);
        vm.expectRevert(); // OZ Ownable custom error selector; generic revert check is sufficient here
        hook.emergencyWithdraw(address(winr), 1);

        // Owner can withdraw a portion of pre-seeded wINR
        uint256 ownerBefore = winr.balanceOf(owner);
        uint256 amount = 123e18;
        // Ensure hook has enough balance
        uint256 hookBal = winr.balanceOf(address(hook));
        if (hookBal < amount) {
            // top-up hook if needed
            winr.transfer(address(hook), amount - hookBal);
        }

        hook.emergencyWithdraw(address(winr), amount);

        assertEq(winr.balanceOf(owner), ownerBefore + amount, "owner should receive withdrawn amount");
    }
}
