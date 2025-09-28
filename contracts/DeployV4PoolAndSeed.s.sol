/**
 * SPDX-License-Identifier: MIT
 *
 * Uniswap v4 pool + hook deploy and seed script.
 *
 * This Foundry script:
 * - Builds a PoolKey for (TOKEN0, TOKEN1) with your hook address and flags
 * - Initializes the pool at a provided sqrtPriceX96
 * - Approves the PositionManager to spend TOKEN0/TOKEN1
 * - Mints an initial liquidity position via MINT_POSITION + SETTLE_PAIR
 *
 * Environment variables expected (export before running):
 *   - PRIVATE_KEY            : Deployer private key (hex, no 0x prefix okay)
 *   - POOL_MANAGER           : Address of deployed Uniswap v4 PoolManager
 *   - POSITION_MANAGER       : Address of deployed PositionManager (periphery)
 *   - TOKEN0                 : Address of token0 (e.g., wINR)
 *   - TOKEN1                 : Address of token1 (e.g., WETH or USDC)
 *   - HOOK_ADDRESS           : Address of your deployed hook
 *   - HOOK_FLAGS             : uint160 bitmask for enabled hook flags (e.g., BEFORE_SWAP|AFTER_SWAP|...)
 *
 * Optional environment variables (with defaults):
 *   - FEE                    : uint24 pool fee                                  (default: 3000)
 *   - TICK_SPACING           : int24 tick spacing                               (default: 60)
 *   - TICK_LOWER             : int24 lower tick bound                           (default: -887220)
 *   - TICK_UPPER             : int24 upper tick bound                           (default:  887220)
 *   - SQRT_PRICE_X96         : uint160 initial sqrt price X96                   (default: 2**96 for 1:1)
 *   - AMOUNT0_MAX            : uint256 max token0 to spend for mint             (default: 1000e18)
 *   - AMOUNT1_MAX            : uint256 max token1 to spend for mint             (default: 1e15)
 *   - RECIPIENT              : Address to receive the minted position/NFT       (default: deployer address)
 *
 * Usage (Sepolia example):
 *   forge script contracts/DeployV4PoolAndSeed.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Notes:
 * - This script assumes your hook is already deployed and its address encodes the correct flags.
 * - If you need to mine/deploy the hook with encoded flags, do that in a separate step (see Uniswap v4 docs).
 * - The PositionManager interface here expects modifyLiquidities(bytes, uint256) batching API.
 */
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "v4-core/src/types/Currency.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";

// Minimal interface for PositionManager; the actual periphery implements this batching API.
interface IPositionManager {
    function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
}

// PositionManager action constants (alignment with v4-periphery Actions.sol)
library PMActions {
    uint8 constant INCREASE_LIQUIDITY = 0x00;
    uint8 constant DECREASE_LIQUIDITY = 0x01;
    uint8 constant MINT_POSITION = 0x02;
    uint8 constant BURN_POSITION = 0x03;

    uint8 constant SETTLE_PAIR = 0x0d;
    uint8 constant TAKE_PAIR = 0x11;
    uint8 constant CLOSE_CURRENCY = 0x12;
    uint8 constant CLEAR_OR_TAKE = 0x13;
}

contract DeployV4PoolAndSeed is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Defaults (can be overridden via env)
    uint24 public constant DEFAULT_FEE = 3000; // 0.3%
    int24 public constant DEFAULT_TICK_SPACING = 60;
    int24 public constant DEFAULT_TICK_LOWER = -887220;
    int24 public constant DEFAULT_TICK_UPPER = 887220;

    // 1:1 price sqrt(1) in X96 format
    uint160 public constant SQRT_PRICE_1_TO_1_X96 = uint160(1) << 96;

    // Default mint budgets (tune for your environment)
    uint256 public constant DEFAULT_AMOUNT0_MAX = 1_000e18; // token0 (e.g., wINR)
    uint256 public constant DEFAULT_AMOUNT1_MAX = 1e15; // token1 (e.g., 0.001 WETH)

    function run() external {
        // Load required env vars
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address positionManagerAddr = vm.envAddress("POSITION_MANAGER");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");

        // Hook flags define which hooks are enabled; ensure they match the hook's encoded address.
        // Example: BEFORE_SWAP | AFTER_SWAP | BEFORE_ADD_LIQUIDITY | BEFORE_REMOVE_LIQUIDITY
        uint160 hookFlags = uint160(vm.envUint("HOOK_FLAGS"));

        // Optional overrides
        uint24 fee = _envOrDefaultUint24("FEE", DEFAULT_FEE);
        int24 tickSpacing = _envOrDefaultInt24("TICK_SPACING", DEFAULT_TICK_SPACING);
        int24 tickLower = _envOrDefaultInt24("TICK_LOWER", DEFAULT_TICK_LOWER);
        int24 tickUpper = _envOrDefaultInt24("TICK_UPPER", DEFAULT_TICK_UPPER);

        uint160 sqrtPriceX96 = _envOrDefaultUint160("SQRT_PRICE_X96", SQRT_PRICE_1_TO_1_X96);

        uint256 amount0Max = _envOrDefaultUint256("AMOUNT0_MAX", DEFAULT_AMOUNT0_MAX);
        uint256 amount1Max = _envOrDefaultUint256("AMOUNT1_MAX", DEFAULT_AMOUNT1_MAX);

        address recipient = _envOrDefaultAddress("RECIPIENT", address(0));
        if (recipient == address(0)) {
            recipient = vm.addr(deployerPk);
        }

        require(poolManagerAddr != address(0), "POOL_MANAGER is required");
        require(positionManagerAddr != address(0), "POSITION_MANAGER is required");
        require(token0 != address(0) && token1 != address(0), "TOKEN0/TOKEN1 are required");
        require(token0 != token1, "TOKEN0 and TOKEN1 must differ");
        require(hookAddress != address(0), "HOOK_ADDRESS is required");
        require(hookFlags != 0, "HOOK_FLAGS must be nonzero");

        console.log("PoolManager:      ", poolManagerAddr);
        console.log("PositionManager:  ", positionManagerAddr);
        console.log("Token0:           ", token0);
        console.log("Token1:           ", token1);
        console.log("Hook:             ", hookAddress);
        console.log("Hook Flags:       ", hookFlags);
        console.log("Fee:              ", fee);
        console.log("TickSpacing:      ", tickSpacing);
        console.log("TickLower:        ", int256(tickLower));
        console.log("TickUpper:        ", int256(tickUpper));
        console.log("SqrtPriceX96:     ", sqrtPriceX96);
        console.log("Max spend token0: ", amount0Max);
        console.log("Max spend token1: ", amount1Max);
        console.log("Recipient:        ", recipient);

        IPoolManager poolManager = IPoolManager(poolManagerAddr);
        IPositionManager positionManager = IPositionManager(positionManagerAddr);

        vm.startBroadcast(deployerPk);

        // Construct the PoolKey with the hook address + flags encoded
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });

        // Initialize the pool at the provided sqrt price
        poolManager.initialize(key, sqrtPriceX96);
        console.log("Initialized pool at sqrtPriceX96 = ", sqrtPriceX96);

        // Approve PositionManager to settle token spends (only if needed)
        // (If your PositionManager pulls via permit or callback, adjust accordingly.)
        uint256 allowance0 = IERC20(token0).allowance(address(this), positionManagerAddr);
        if (allowance0 < amount0Max) {
            // Set to max to avoid repeated approvals
            IERC20(token0).approve(positionManagerAddr, type(uint256).max);
        }
        uint256 allowance1 = IERC20(token1).allowance(address(this), positionManagerAddr);
        if (allowance1 < amount1Max) {
            IERC20(token1).approve(positionManagerAddr, type(uint256).max);
        }

        // Mint initial liquidity via batched commands:
        // Sequence: MINT_POSITION (creates negative deltas) -> SETTLE_PAIR (pays tokens)
        bytes memory actions = abi.encodePacked(PMActions.MINT_POSITION, PMActions.SETTLE_PAIR);

        // Pick an initial liquidity "target".
        // The exact token deltas will be computed by PM given current price; we resolve via SETTLE_PAIR.
        uint128 liquidity = uint128(1_000_000); // nominal seed; adjust as needed

        // Params for MINT_POSITION:
        // (poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData)
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            uint128(amount0Max),
            uint128(amount1Max),
            recipient,
            bytes("") // hook data, if any
        );

        // Params for SETTLE_PAIR: (currency0, currency1)
        params[1] = abi.encode(key.currency0, key.currency1);

        // Execute the batched modifyLiquidities
        bytes memory payload = abi.encode(actions, params);
        positionManager.modifyLiquidities(payload, block.timestamp + 900);

        PoolId poolId = key.toId();
        console.log("Seed liquidity added. PoolId:");
        console.logBytes32(PoolId.unwrap(poolId));

        vm.stopBroadcast();
    }

    // Helpers to read env with defaults

    function _envOrDefaultUint24(string memory key, uint24 def) internal view returns (uint24) {
        (bool ok, uint256 v) = _tryEnvUint(key);
        return ok ? uint24(v) : def;
    }

    function _envOrDefaultInt24(string memory key, int24 def) internal view returns (int24) {
        (bool ok, uint256 v) = _tryEnvUint(key);
        return ok ? int24(int256(v)) : def;
    }

    function _envOrDefaultUint160(string memory key, uint160 def) internal view returns (uint160) {
        (bool ok, uint256 v) = _tryEnvUint(key);
        return ok ? uint160(v) : def;
    }

    function _envOrDefaultUint256(string memory key, uint256 def) internal view returns (uint256) {
        (bool ok, uint256 v) = _tryEnvUint(key);
        return ok ? v : def;
    }

    function _envOrDefaultAddress(string memory key, address def) internal view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a;
        } catch {
            return def;
        }
    }

    function _tryEnvUint(string memory key) internal view returns (bool, uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return (true, v);
        } catch {
            return (false, 0);
        }
    }
}
