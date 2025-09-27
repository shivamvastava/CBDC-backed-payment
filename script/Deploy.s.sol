// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WINR} from "../contracts/WINR.sol";
import {AMLSwapHook} from "../contracts/AMLSwapHook.sol";
import {TokenConversionService} from "../contracts/TokenConversionService.sol";
import {PoolFactory} from "../contracts/PoolFactory.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title Deployment Script
 * @dev Script to deploy the CBDC payment system contracts
 */
contract DeployScript is Script {
    // Contract addresses (will be set during deployment)
    address public winr;
    address public amlHook;
    address public conversionService;
    address public poolFactory;
    
    // Configuration
    uint256 public constant INITIAL_WINR_SUPPLY = 100_000_000 * 10**18; // 100 million wINR
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy WINR token
        console.log("Deploying WINR token...");
        WINR winrContract = new WINR(INITIAL_WINR_SUPPLY);
        winr = address(winrContract);
        console.log("WINR deployed at:", winr);
        
        // Deploy Token Conversion Service
        console.log("Deploying Token Conversion Service...");
        TokenConversionService conversionServiceContract = new TokenConversionService(winr);
        conversionService = address(conversionServiceContract);
        console.log("Token Conversion Service deployed at:", conversionService);
        
        // Transfer some WINR to the conversion service
        uint256 conversionServiceAmount = 10_000_000 * 10**18; // 10 million wINR
        winrContract.transfer(conversionService, conversionServiceAmount);
        console.log("Transferred", conversionServiceAmount / 1e18, "wINR to conversion service");
        
        // Deploy Pool Factory
        console.log("Deploying Pool Factory...");
        // Note: In production, you'd use the actual PoolManager address
        address poolManagerAddress = vm.envOr("POOL_MANAGER_ADDRESS", address(0));
        require(poolManagerAddress != address(0), "POOL_MANAGER_ADDRESS not set");
        
        PoolFactory poolFactoryContract = new PoolFactory(IPoolManager(poolManagerAddress), winr);
        poolFactory = address(poolFactoryContract);
        console.log("Pool Factory deployed at:", poolFactory);
        
        // Deploy AML Hook
        console.log("Deploying AML Hook...");
        AMLSwapHook amlHookContract = new AMLSwapHook(IPoolManager(poolManagerAddress), winr);
        amlHook = address(amlHookContract);
        console.log("AML Hook deployed at:", amlHook);
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("WINR Token:", winr);
        console.log("Token Conversion Service:", conversionService);
        console.log("Pool Factory:", poolFactory);
        console.log("AML Hook:", amlHook);
        console.log("Initial wINR Supply:", INITIAL_WINR_SUPPLY / 1e18, "wINR");
        console.log("Conversion Service Balance:", conversionServiceAmount / 1e18, "wINR");
        
        // Save deployment addresses to file
        _saveDeploymentAddresses();
    }
    
    function _saveDeploymentAddresses() internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "WINR_TOKEN=", vm.toString(winr), "\n",
            "TOKEN_CONVERSION_SERVICE=", vm.toString(conversionService), "\n",
            "POOL_FACTORY=", vm.toString(poolFactory), "\n",
            "AML_HOOK=", vm.toString(amlHook), "\n"
        ));
        
        vm.writeFile("deployment.env", deploymentInfo);
        console.log("Deployment addresses saved to deployment.env");
    }
}
