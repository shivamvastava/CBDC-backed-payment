// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WINR} from "../contracts/WINR.sol";
import {SimpleAMLHook} from "../contracts/SimpleAMLHook.sol";
import {TokenConversionService} from "../contracts/TokenConversionService.sol";
import {SimplePoolFactory} from "../contracts/SimplePoolFactory.sol";

/**
 * @title Simple Deployment Script
 * @dev Script to deploy the core CBDC payment system contracts
 */
contract SimpleDeployScript is Script {
    // Contract addresses (will be set during deployment)
    address public winr;
    address public amlHook;
    address public conversionService;
    address public poolFactory;
    
    // Configuration
    uint256 public constant INITIAL_WINR_SUPPLY = 100_000_000 * 10**18; // 100 million wINR
    uint256 public constant CONVERSION_SERVICE_BALANCE = 10_000_000 * 10**18; // 10 million wINR for conversion
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy WINR Token
        console.log("Deploying WINR Token...");
        WINR winrContract = new WINR(INITIAL_WINR_SUPPLY);
        winr = address(winrContract);
        console.log("WINR Token deployed at:", winr);
        
        // Deploy Simple AML Hook
        console.log("Deploying Simple AML Hook...");
        SimpleAMLHook amlHookContract = new SimpleAMLHook(winr);
        amlHook = address(amlHookContract);
        console.log("Simple AML Hook deployed at:", amlHook);
        
        // Deploy Token Conversion Service
        console.log("Deploying Token Conversion Service...");
        TokenConversionService conversionServiceContract = new TokenConversionService(winr);
        conversionService = address(conversionServiceContract);
        console.log("Token Conversion Service deployed at:", conversionService);
        
        // Transfer wINR to conversion service
        console.log("Transferring", CONVERSION_SERVICE_BALANCE / 1e18, "wINR to conversion service...");
        winrContract.transfer(conversionService, CONVERSION_SERVICE_BALANCE);
        console.log("Transferred", CONVERSION_SERVICE_BALANCE / 1e18, "wINR to conversion service");
        
        // Deploy Simple Pool Factory
        console.log("Deploying Simple Pool Factory...");
        SimplePoolFactory poolFactoryContract = new SimplePoolFactory(winr);
        poolFactory = address(poolFactoryContract);
        console.log("Simple Pool Factory deployed at:", poolFactory);
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("WINR Token:", winr);
        console.log("Simple AML Hook:", amlHook);
        console.log("Token Conversion Service:", conversionService);
        console.log("Simple Pool Factory:", poolFactory);
        console.log("Initial wINR Supply:", INITIAL_WINR_SUPPLY / 1e18, "wINR");
        console.log("Conversion Service Balance:", CONVERSION_SERVICE_BALANCE / 1e18, "wINR");
        console.log("Deployer Balance:", winrContract.balanceOf(deployer) / 1e18, "wINR");
        
        // Save deployment addresses to file
        _saveDeploymentAddresses();
    }
    
    function _saveDeploymentAddresses() internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "WINR_TOKEN=", vm.toString(winr), "\n",
            "SIMPLE_AML_HOOK=", vm.toString(amlHook), "\n",
            "TOKEN_CONVERSION_SERVICE=", vm.toString(conversionService), "\n",
            "SIMPLE_POOL_FACTORY=", vm.toString(poolFactory), "\n"
        ));
        
        vm.writeFile("deployment.env", deploymentInfo);
        console.log("Deployment addresses saved to deployment.env");
    }
}