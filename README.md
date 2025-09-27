# CBDC-Backed Payments System

A comprehensive CBDC (Central Bank Digital Currency) payment system with integrated AML (Anti-Money Laundering) compliance and automatic token conversion capabilities. This repository is simplified and Uniswap-independent, focusing on core modules only.

## Overview

This system implements a wrapped Indian Rupee (wINR) token with the following key features:

1. ERC20 wINR Token: A compliant wrapped Indian Rupee token with built-in blacklisting and pause functionality
2. Simple AML Hook: Real-time AML compliance checking for transactions
3. Token Conversion Service: Automatic conversion of authorized tokens to wINR
4. Simple Pool Factory: Lightweight pool registry for wINR/token pairs

## Architecture

### Core Components

- contracts/WINR.sol: ERC20 token representing wrapped Indian Rupee (wINR)
- contracts/SimpleAMLHook.sol: Simplified AML compliance checks and configuration
- contracts/TokenConversionService.sol: Service for converting authorized tokens to wINR
- contracts/SimplePoolFactory.sol: Lightweight factory and registry for pools

### Key Features

- AML Compliance
  - Real-time blacklist checking for participants
  - Configurable blacklist management
  - Basic compliance event logging

- Token Conversion
  - Support for multiple authorized tokens (e.g., USDC, USDT)
  - Configurable conversion rates
  - Daily conversion limits per user
  - Minimum and maximum conversion amounts

- Regulatory Controls
  - Pause/unpause functionality
  - Owner-controlled administrative functions
  - Emergency withdrawal capabilities

## Installation

### Prerequisites

- Foundry
- Node.js 16+
- Git

### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd CBDC-backed-payment
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

## Deployment

### Environment Setup

Create a `.env` file:
```bash
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_project_id
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_project_id
```

### Deploy Contracts

1. Deploy to local network:
```bash
forge script script/SimpleDeploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

2. Deploy to Sepolia testnet:
```bash
forge script script/SimpleDeploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

3. Deploy to mainnet:
```bash
forge script script/SimpleDeploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
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

### 2. Simple AML Hook Configuration

```solidity
// Add address to blacklist
amlHook.updateBlacklist(user, true);

// Authorize token for conversion metadata (if used downstream)
amlHook.updateAuthorizedToken(token, true);

// Set conversion rate metadata
amlHook.updateConversionRate(token, rate);
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

### 4. Simple Pool Factory

```solidity
// Create new wINR/token pool record
uint256 poolId = poolFactory.createPool(
    token1,   // the non-wINR token
    3000,     // fee (arbitrary metadata)
    address(amlHook) // optional hook reference
);
```

## Security Considerations

- Access Control
  - All administrative functions are restricted to the contract owner
  - Emergency functions are available for critical situations
  - Pause functionality prevents malicious activities

- AML Compliance
  - Blacklist checking prevents sanctioned addresses from participating
  - Compliance-related events for audit trails

- Token Security
  - Maximum supply limits prevent inflation
  - Blacklist functionality for regulatory compliance
  - Pause mechanism for emergency situations

## Monitoring and Events

Key events:
- AddressBlacklisted
- TokensConverted
- TokensMinted/TokensBurned

Use these events for:
- Compliance tracking
- System health monitoring
- User activity analysis
- Security incident triage

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This software is provided for educational and development purposes. Use in production requires thorough security auditing and compliance verification with local regulations.
