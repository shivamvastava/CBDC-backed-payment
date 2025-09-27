# Makefile for CBDC-Backed Payments System

.PHONY: help build test test-verbose test-gas clean deploy-local deploy-sepolia deploy-mainnet lint coverage

# Default target
help:
	@echo "CBDC-Backed Payments System - Available Commands:"
	@echo ""
	@echo "Development:"
	@echo "  build          - Build all contracts"
	@echo "  test           - Run all tests"
	@echo "  test-verbose   - Run tests with verbose output"
	@echo "  test-gas       - Run tests with gas reporting"
	@echo "  coverage       - Run test coverage analysis"
	@echo "  lint           - Format code with forge fmt"
	@echo "  clean          - Clean build artifacts"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy-local   - Deploy to local network"
	@echo "  deploy-sepolia - Deploy to Sepolia testnet"
	@echo "  deploy-mainnet - Deploy to mainnet"

	@echo ""
	@echo "Utilities:"
	@echo "  install        - Install dependencies"
	@echo "  update         - Update dependencies"
	@echo "  size           - Check contract sizes"
	@echo "  gas-report     - Generate gas report"

# Development commands
build:
	forge build

test:
	forge test

test-verbose:
	forge test -vvv

test-gas:
	forge test --gas-report

coverage:
	forge coverage

lint:
	forge fmt

clean:
	forge clean

# Deployment commands
deploy-local:
	forge script script/SimpleDeploy.s.sol --rpc-url http://localhost:8545 --broadcast

deploy-sepolia:
	forge script script/SimpleDeploy.s.sol --rpc-url $$SEPOLIA_RPC_URL --broadcast --verify

deploy-mainnet:
	forge script script/SimpleDeploy.s.sol --rpc-url $$MAINNET_RPC_URL --broadcast --verify



# Utility commands
install:
	forge install

update:
	forge update

size:
	forge build --sizes

gas-report:
	forge test --gas-report > gas-report.txt

# Test specific contracts
test-winr:
	forge test --match-contract WINRTest



test-conversion:
	forge test --match-contract TokenConversionServiceTest



# Security and analysis
slither:
	slither .

mythril:
	mythril analyze contracts/ --execution-timeout 300

# Documentation
docs:
	forge doc --build

# Environment setup
env-setup:
	cp env.example .env
	@echo "Please edit .env file with your configuration"

# Quick start
quick-start: env-setup install build test
	@echo "Quick start complete! Run 'make deploy-local' to deploy to local network"
