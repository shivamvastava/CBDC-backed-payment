// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WINR} from "../contracts/WINR.sol";
import {AMLSwapHook} from "../contracts/AMLSwapHook.sol";
import {TokenConversionService} from "../contracts/TokenConversionService.sol";
import {PoolFactory} from "../contracts/PoolFactory.sol";

/**
 * @title Setup Script
 * @dev Script to configure the deployed CBDC payment system contracts
 */
contract SetupScript is Script {
    // Contract addresses (load from deployment.env)
    address public winr;
    address public amlHook;
    address public conversionService;
    address public poolFactory;
    
    // Configuration
    address public constant USDC = 0xA0b86a33E6441b8c4C8C0C4C0C4C0C4C0C4C0C4C; // Example USDC address
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Example USDT address
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load contract addresses from deployment.env
        _loadDeploymentAddresses();
        
        console.log("Setting up contracts with account:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Setup Token Conversion Service
        _setupTokenConversionService();
        
        // Setup AML Hook
        _setupAMLHook();
        
        // Setup Pool Factory
        _setupPoolFactory();
        
        vm.stopBroadcast();
        
        console.log("\n=== Setup Complete ===");
        console.log("All contracts have been configured successfully");
    }
    
    function _loadDeploymentAddresses() internal {
        // In a real deployment, you'd load these from deployment.env
        // For this example, we'll use placeholder addresses
        winr = vm.envOr("WINR_TOKEN", address(0));
        conversionService = vm.envOr("TOKEN_CONVERSION_SERVICE", address(0));
        poolFactory = vm.envOr("POOL_FACTORY", address(0));
        amlHook = vm.envOr("AML_HOOK", address(0));
        
        require(winr != address(0), "WINR_TOKEN not set");
        require(conversionService != address(0), "TOKEN_CONVERSION_SERVICE not set");
        require(poolFactory != address(0), "POOL_FACTORY not set");
        require(amlHook != address(0), "AML_HOOK not set");
    }
    
    function _setupTokenConversionService() internal {
        console.log("Setting up Token Conversion Service...");
        
        TokenConversionService service = TokenConversionService(conversionService);
        
        // Authorize USDC for conversion
        service.updateAuthorizedToken(USDC, true);
        console.log("Authorized USDC for conversion");
        
        // Set conversion rate (1 USDC = 83 wINR, example rate)
        service.updateConversionRate(USDC, 83 * 1e18);
        console.log("Set USDC conversion rate to 83 wINR per USDC");
        
        // Set minimum conversion amount (100 USDC)
        service.updateMinimumConversionAmount(USDC, 100 * 1e6);
        console.log("Set minimum USDC conversion amount to 100 USDC");
        
        // Set maximum conversion amount (100,000 USDC)
        service.updateMaximumConversionAmount(USDC, 100000 * 1e6);
        console.log("Set maximum USDC conversion amount to 100,000 USDC");
        
        // Authorize USDT for conversion
        service.updateAuthorizedToken(USDT, true);
        console.log("Authorized USDT for conversion");
        
        // Set conversion rate (1 USDT = 83 wINR, example rate)
        service.updateConversionRate(USDT, 83 * 1e18);
        console.log("Set USDT conversion rate to 83 wINR per USDT");
        
        // Set minimum conversion amount (100 USDT)
        service.updateMinimumConversionAmount(USDT, 100 * 1e6);
        console.log("Set minimum USDT conversion amount to 100 USDT");
        
        // Set maximum conversion amount (100,000 USDT)
        service.updateMaximumConversionAmount(USDT, 100000 * 1e6);
        console.log("Set maximum USDT conversion amount to 100,000 USDT");
    }
    
    function _setupAMLHook() internal {
        console.log("Setting up AML Hook...");
        
        AMLSwapHook hook = AMLSwapHook(amlHook);
        
        // Add some example blacklisted addresses
        address[] memory blacklistedAddresses = new address[](3);
        blacklistedAddresses[0] = 0x0000000000000000000000000000000000000001;
        blacklistedAddresses[1] = 0x0000000000000000000000000000000000000002;
        blacklistedAddresses[2] = 0x0000000000000000000000000000000000000003;
        
        for (uint256 i = 0; i < blacklistedAddresses.length; i++) {
            hook.updateBlacklist(blacklistedAddresses[i], true);
            console.log("Blacklisted address:", blacklistedAddresses[i]);
        }
    }
    
    function _setupPoolFactory() internal {
        console.log("Setting up Pool Factory...");
        
        // The pool factory is already configured during deployment
        // Additional setup can be added here if needed
        console.log("Pool Factory setup complete");
    }
}
