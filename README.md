# CBDC-Backed Payments System

A comprehensive CBDC (Central Bank Digital Currency) payment system built on Uniswap V4 hooks with integrated AML (Anti-Money Laundering) compliance and automatic token conversion capabilities.

## Overview

This system implements a wrapped Indian Rupee (wINR) token with the following key features:

1. **ERC20 wINR Token**: A compliant wrapped Indian Rupee token with built-in blacklisting and pause functionality
2. **Uniswap V4 AML Hook**: Real-time AML compliance checking for all swap transactions
3. **Token Conversion Service**: Automatic conversion of authorized tokens to wINR
4. **Pool Factory**: Automated creation of wINR/ETH liquidity pools with integrated hooks

## Architecture

### Core Components

- **WINR.sol**: ERC20 token representing wrapped Indian Rupee
- **AMLSwapHook.sol**: Uniswap V4 hook for AML compliance and token conversion
- **TokenConversionService.sol**: Service for converting authorized tokens to wINR
- **PoolFactory.sol**: Factory for creating wINR/ETH pools with hooks

### Key Features

#### 1. AML Compliance
- Real-time blacklist checking for all swap participants
- Configurable blacklist management
- Event logging for compliance tracking

#### 2. Automatic Token Conversion
- Support for multiple authorized tokens (USDC, USDT, etc.)
- Configurable conversion rates
- Daily conversion limits per user
- Minimum and maximum conversion amounts

#### 3. Regulatory Compliance
- Pause/unpause functionality
- Owner-controlled administrative functions
- Comprehensive event logging
- Emergency withdrawal capabilities

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+
- Git

### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd CBDC-backed-payments
```

2. Install dependencies:
```bash
forge install
```

3. Build the contracts:
```bash
forge build
```

## Testing

Run the comprehensive test suite:

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vvv

# Run tests with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-contract WINRTest
```

### Test Coverage

The test suite includes:
- Unit tests for each contract
- Integration tests for end-to-end workflows
- Fuzz testing for edge cases
- Gas optimization tests

## Deployment

### Environment Setup

1. Create a `.env` file:
```bash
PRIVATE_KEY=your_private_key_here
POOL_MANAGER_ADDRESS=uniswap_v4_pool_manager_address
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_project_id
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_project_id
```

### Deploy Contracts

1. Deploy to local network:
```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

2. Deploy to Sepolia testnet:
```bash
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

3. Deploy to mainnet:
```bash
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

### Post-Deployment Setup

Run the setup script to configure the deployed contracts:

```bash
forge script script/Setup.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

## Usage

### 1. WINR Token Operations

```solidity
// Mint new tokens (owner only)
winr.mint(user, amount);

// Burn tokens
winr.burn(amount);

// Update blacklist
winr.updateBlacklist(user, true);

// Pause/unpause transfers
winr.pause();
winr.unpause();
```

### 2. AML Hook Configuration

```solidity
// Add address to blacklist
hook.updateBlacklist(user, true);

// Authorize token for conversion
hook.updateAuthorizedToken(token, true);

// Set conversion rate
hook.updateConversionRate(token, rate);
```

### 3. Token Conversion

```solidity
// Convert authorized token to wINR
uint256 wINRAmount = conversionService.convertToWINR(token, amount);

// Get conversion quote
uint256 quote = conversionService.getConversionQuote(token, amount);

// Check remaining daily limit
uint256 remaining = conversionService.getRemainingDailyLimit(user, token);
```

### 4. Pool Creation

```solidity
// Create new wINR/ETH pool
(PoolId poolId, address hook) = poolFactory.createPool(
    fee,           // Pool fee (e.g., 3000 for 0.3%)
    tickSpacing,   // Tick spacing
    initialSqrtPriceX96  // Initial price
);
```

## Security Considerations

### Access Control
- All administrative functions are restricted to the contract owner
- Emergency functions are available for critical situations
- Pause functionality prevents malicious activities

### AML Compliance
- Real-time blacklist checking prevents sanctioned addresses from participating
- Comprehensive event logging for audit trails
- Configurable compliance parameters

### Token Security
- Maximum supply limits prevent inflation
- Blacklist functionality for regulatory compliance
- Pause mechanism for emergency situations

## Gas Optimization

The contracts are optimized for gas efficiency:
- Efficient data structures for O(1) lookups
- Minimal storage operations
- Optimized function implementations

## Monitoring and Events

### Key Events

- `AddressBlacklisted`: When an address is added/removed from blacklist
- `TokensConverted`: When tokens are converted to wINR
- `SwapBlocked`: When a swap is blocked due to AML compliance
- `TokensMinted/Burned`: Token supply changes

### Monitoring

Monitor these events for:
- Compliance tracking
- System health
- User activity
- Security incidents

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue in the repository
- Contact the development team
- Check the documentation

## Roadmap

- [ ] Integration with real-time AML databases
- [ ] Multi-chain support
- [ ] Advanced compliance features
- [ ] User interface development
- [ ] Mobile application
- [ ] API documentation
- [ ] Performance optimizations

## Disclaimer

This software is provided for educational and development purposes. Use in production requires thorough security auditing and compliance verification with local regulations.
# CBDC-backed-payment
