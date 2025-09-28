/Volumes/Code/ETHGlobal/CBDC-backed-payment/contracts/AMLSwapHook.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AMLSwapHook - Uniswap V4 Hook for AML Compliance and Token Conversion
 * @dev This hook implements:
 *      1. AML/sanctions checking for blacklisted addresses
 *      2. Optional conversion of authorized tokens to wINR before swaps
 *      3. Compliance tracking and reporting
 * @notice Designed for CBDC-backed payment systems with regulatory compliance
 *
 * Permissions:
 * - getHookPermissions() indicates which hook methods are enabled.
 * - This implementation enables beforeSwap (without return delta).
 */
contract AMLSwapHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // wINR token address
    address public immutable wINR;

    // Mapping to track blacklisted addresses
    mapping(address => bool) public blacklisted;

    // Mapping to track authorized tokens that can be converted to wINR
    mapping(address => bool) public authorizedTokens;

    // Mapping to store conversion rates (token => rate per wINR, scaled by 1e18)
    mapping(address => uint256) public conversionRates;

    // Events for compliance and monitoring
    event AddressBlacklisted(address indexed account, bool status);
    event TokenAuthorized(address indexed token, bool status);
    event ConversionRateUpdated(address indexed token, uint256 rate);
    event SwapBlocked(address indexed user, string reason);
    event TokenConverted(address indexed user, address indexed fromToken, uint256 amount, uint256 wINRAmount);

    // Modifier to check if address is not blacklisted
    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "AMLSwapHook: Address is blacklisted");
        _;
    }

    /**
     * @dev Constructor
     * @param _poolManager Uniswap V4 PoolManager address
     * @param _wINR wINR token address
     */
    constructor(IPoolManager _poolManager, address _wINR) BaseHook(_poolManager) Ownable(msg.sender) {
        require(address(_poolManager) != address(0), "AMLSwapHook: invalid PoolManager");
        require(_wINR != address(0), "AMLSwapHook: Invalid wINR address");
        wINR = _wINR;
    }

    /**
     * @dev Get hook permissions
     * @return Permissions struct defining which hooks are enabled
     *
     * Note:
     * - We only enable beforeSwap.
     * - We do NOT use beforeSwapReturnDelta, so beforeSwap returns only bytes4.
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @dev Hook called before swap execution
     * @param sender Address initiating the swap
     * @param key Pool key containing token addresses and fee
     * @param params Swap parameters
     * @param hookData Additional data passed to the hook
     * @return Hook return value (selector)
     *
     * Behavior:
     * - Enforces AML checks on the sender (and optionally recipient if encoded in hookData).
     * - Demonstrates token conversion flow if input token is authorized and not wINR
     *   (simple accounting example; adjust in production).
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // AML Compliance Check (recipient optional and can be provided via hookData)
        address recipient = _recipientFromHookData(hookData);
        _performAMLCheck(sender, recipient);

        // Token Conversion (illustrative; production systems should integrate robust pricing/oracle flows)
        _handleTokenConversion(sender, key, params);

        return BaseHook.beforeSwap.selector;
    }

    /**
     * @dev Perform AML compliance checks
     * @param sender Address initiating the transaction
     * @param recipient Address receiving the tokens (can be address(0) if not applicable)
     */
    function _performAMLCheck(address sender, address recipient) internal view {
        if (blacklisted[sender]) {
            // block sender
            // NOTE: Emitting an event before revert is fine for observability
            // but costs gas; keep as needed for auditing.
            // (Events emitted pre-revert are still included in tx logs.)
            // A more gas-optimized approach could omit the event here.
            // For compliance traceability, we keep it.
            // solhint-disable-next-line reason-string
            revertWithLog(sender, "Sender is blacklisted");
        }

        if (recipient != address(0) && blacklisted[recipient]) {
            revertWithLog(recipient, "Recipient is blacklisted");
        }
    }

    /**
     * @dev Internal helper for logging and reverting on AML check failure
     */
    function revertWithLog(address user, string memory reason) internal pure {
        // emit event (readers can reconstruct cause)
        // NOTE: Since this is view in _performAMLCheck, we don't emit here.
        // To keep parity with examples, we keep explicit helper but don't emit from view context.
        // The revert reason carries the message.
        revert(string(abi.encodePacked("AMLSwapHook: ", reason)));
    }

    /**
     * @dev Extract recipient from hookData if provided (abi.encodePacked(address) or empty)
     * @param hookData Optional abi-encoded recipient address; returns address(0) if not present or invalid
     */
    function _recipientFromHookData(bytes calldata hookData) internal pure returns (address) {
        if (hookData.length == 20) {
            // raw 20-byte address
            address r;
            assembly {
                r := shr(96, calldataload(hookData.offset))
            }
            return r;
        } else if (hookData.length == 32) {
            // abi.encode(address) style
            return abi.decode(hookData, (address));
        }
        return address(0);
    }

    /**
     * @dev Handle automatic token conversion to wINR (illustrative)
     * @param sender Address initiating the swap
     * @param key Pool key
     * @param params Swap parameters
     *
     * Notes:
     * - If input token is not wINR and is authorized, we perform a naive conversion by
     *   pulling tokens from the sender and transferring equivalent wINR.
     * - This is only a demonstration. In production, integrate with a conversion service,
     *   use trusted oracles for pricing, and handle approvals/liquidity properly.
     */
    function _handleTokenConversion(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal {
        address tokenIn = Currency.unwrap(params.zeroForOne ? key.currency0 : key.currency1);

        // If the input token is not wINR and is authorized for conversion
        if (tokenIn != wINR && authorizedTokens[tokenIn]) {
            // Perform simplified conversion for demonstration purposes
            _convertToWINR(sender, tokenIn, params.amountSpecified);
        }
    }

    /**
     * @dev Convert authorized token to wINR
     * @param user Address performing the conversion
     * @param token Address of the token to convert
     * @param amount Amount to convert (can be negative for exact output swaps)
     */
    function _convertToWINR(address user, address token, int256 amount) internal {
        require(amount != 0, "AMLSwapHook: Invalid conversion amount");
        uint256 rate = conversionRates[token];
        require(rate > 0, "AMLSwapHook: No conversion rate set");

        // Handle both positive and negative amounts
        uint256 fromAmount = amount > 0 ? uint256(amount) : uint256(-amount);
        uint256 wINRAmount = (fromAmount * rate) / 1e18;
        require(wINRAmount > 0, "AMLSwapHook: Conversion results in zero wINR");

        // Transfer input token from user to this contract
        IERC20(token).safeTransferFrom(user, address(this), fromAmount);

        // Transfer wINR from this contract to user (assumes pre-funded)
        IERC20(wINR).safeTransfer(user, wINRAmount);

        emit TokenConverted(user, token, fromAmount, wINRAmount);
    }

    // -----------------------
    // Admin / Owner Functions
    // -----------------------

    /**
     * @dev Add or remove address from blacklist (only owner)
     * @param account Address to blacklist/unblacklist
     * @param status True to blacklist, false to remove from blacklist
     */
    function updateBlacklist(address account, bool status) external onlyOwner {
        require(account != address(0), "AMLSwapHook: Cannot blacklist zero address");
        blacklisted[account] = status;
        emit AddressBlacklisted(account, status);
    }

    /**
     * @dev Authorize or deauthorize token for conversion (only owner)
     * @param token Token address
     * @param status True to authorize, false to deauthorize
     */
    function updateAuthorizedToken(address token, bool status) external onlyOwner {
        require(token != address(0), "AMLSwapHook: Invalid token address");
        authorizedTokens[token] = status;
        emit TokenAuthorized(token, status);
    }

    /**
     * @dev Update conversion rate for a token (only owner)
     * @param token Token address
     * @param rate Conversion rate (token per wINR, scaled by 1e18)
     */
    function updateConversionRate(address token, uint256 rate) external onlyOwner {
        require(token != address(0), "AMLSwapHook: Invalid token address");
        require(rate > 0, "AMLSwapHook: Invalid conversion rate");
        conversionRates[token] = rate;
        emit ConversionRateUpdated(token, rate);
    }

    // -------------
    // View Helpers
    // -------------

    /**
     * @dev Check if an address is blacklisted
     * @param account Address to check
     * @return True if blacklisted, false otherwise
     */
    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }

    /**
     * @dev Check if a token is authorized for conversion
     * @param token Token address to check
     * @return True if authorized, false otherwise
     */
    function isAuthorizedToken(address token) external view returns (bool) {
        return authorizedTokens[token];
    }

    /**
     * @dev Get conversion rate for a token
     * @param token Token address
     * @return Conversion rate
     */
    function getConversionRate(address token) external view returns (uint256) {
        return conversionRates[token];
    }

    // -----------------
    // Emergency / Ops
    // -----------------

    /**
     * @dev Emergency function to withdraw stuck tokens (only owner)
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "AMLSwapHook: Invalid token address");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
