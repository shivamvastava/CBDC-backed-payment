/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";

import {AMLSwapHook} from "../contracts/AMLSwapHook.sol";
import {WINR} from "../contracts/WINR.sol";

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
            hooks: bytes21(0)
        });

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(1e18),
            sqrtPriceLimitX96: uint160(1) << 96
        });

        // Expect revert on blacklisted sender
        vm.expectRevert(bytes("AMLSwapHook: Sender is blacklisted"));
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
            hooks: bytes21(0)
        });

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(1e18),
            sqrtPriceLimitX96: uint160(1) << 96
        });

        // Provide recipient in hookData (abi.encode(address))
        bytes memory hookData = abi.encode(userBlacklisted);

        // Expect revert on blacklisted recipient
        vm.expectRevert(bytes("AMLSwapHook: Recipient is blacklisted"));
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
            hooks: bytes21(0)
        });

        // amountSpecified > 0 (exact input)
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(fromAmount),
            sqrtPriceLimitX96: uint160(1) << 96
        });

        // Record balances
        uint256 userTokenInBefore = tokenIn.balanceOf(userApproved);
        uint256 userWINRBefore = winr.balanceOf(userApproved);
        uint256 hookWINRBefore = winr.balanceOf(address(hook));

        // Act
        vm.prank(address(this)); // caller doesn't matter; our hook does not restrict msg.sender to PoolManager in this override
        hook.beforeSwap(userApproved, key, params, bytes(""));

        // 1:1 conversion expected
        uint256 expectedWINR = fromAmount;

        // Assert: tokenIn pulled from user
        assertEq(tokenIn.balanceOf(userApproved), userTokenInBefore - fromAmount, "user tokenIn should decrease");

        // Assert: user received wINR, hook paid out wINR
        assertEq(winr.balanceOf(userApproved), userWINRBefore + expectedWINR, "user wINR should increase");
        assertEq(winr.balanceOf(address(hook)), hookWINRBefore - expectedWINR, "hook wINR should decrease");
    }
}
