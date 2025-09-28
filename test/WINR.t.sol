// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { WINR } from "../contracts/WINR.sol";

/**
 * @title WINR Token Tests
 * @dev Comprehensive test suite for the WINR token contract
 */
contract WINRTest is Test {
    WINR public winr;
    address public owner;
    address public user1;
    address public user2;
    address public blacklistedUser;

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18; // 100 million tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens

    event AddressBlacklisted(address indexed account, bool status);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        blacklistedUser = makeAddr("blacklistedUser");

        winr = new WINR(INITIAL_SUPPLY);
    }

    function testInitialState() public view {
        assertEq(winr.name(), "Wrapped Indian Rupee");
        assertEq(winr.symbol(), "wINR");
        assertEq(winr.decimals(), 18);
        assertEq(winr.totalSupply(), INITIAL_SUPPLY);
        assertEq(winr.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(winr.getMaxSupply(), MAX_SUPPLY);
    }

    function testMint() public {
        uint256 mintAmount = 50_000_000 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, mintAmount);

        winr.mint(user1, mintAmount);

        assertEq(winr.totalSupply(), INITIAL_SUPPLY + mintAmount);
        assertEq(winr.balanceOf(user1), mintAmount);
    }

    function testMintExceedsMaxSupply() public {
        uint256 excessAmount = MAX_SUPPLY - INITIAL_SUPPLY + 1;

        vm.expectRevert("WINR: Minting would exceed maximum supply");
        winr.mint(user1, excessAmount);
    }

    function testMintToZeroAddress() public {
        vm.expectRevert("WINR: Cannot mint to zero address");
        winr.mint(address(0), 1000);
    }

    function testMintToBlacklistedAddress() public {
        winr.updateBlacklist(user1, true);

        vm.expectRevert("WINR: Cannot mint to blacklisted address");
        winr.mint(user1, 1000);
    }

    function testBurn() public {
        uint256 burnAmount = 10_000_000 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit TokensBurned(owner, burnAmount);

        winr.burn(burnAmount);

        assertEq(winr.totalSupply(), INITIAL_SUPPLY - burnAmount);
        assertEq(winr.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
    }

    function testBurnFrom() public {
        uint256 transferAmount = 5_000_000 * 10 ** 18;
        uint256 burnAmount = 1_000_000 * 10 ** 18;

        // Transfer tokens to user1
        assertTrue(winr.transfer(user1, transferAmount));

        // Burn from user1
        vm.expectEmit(true, false, false, true);
        emit TokensBurned(user1, burnAmount);

        winr.burnFrom(user1, burnAmount);

        assertEq(winr.totalSupply(), INITIAL_SUPPLY - burnAmount);
        assertEq(winr.balanceOf(user1), transferAmount - burnAmount);
    }

    function testUpdateBlacklist() public {
        vm.expectEmit(true, false, false, true);
        emit AddressBlacklisted(user1, true);

        winr.updateBlacklist(user1, true);

        assertTrue(winr.isBlacklisted(user1));

        vm.expectEmit(true, false, false, true);
        emit AddressBlacklisted(user1, false);

        winr.updateBlacklist(user1, false);

        assertFalse(winr.isBlacklisted(user1));
    }

    function testUpdateBlacklistZeroAddress() public {
        vm.expectRevert("WINR: Cannot blacklist zero address");
        winr.updateBlacklist(address(0), true);
    }

    function testTransferToBlacklistedAddress() public {
        winr.updateBlacklist(user1, true);

        vm.expectRevert("WINR: Recipient is blacklisted");
        address(winr).call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), user1, 1000));
    }

    function testTransferFromBlacklistedAddress() public {
        assertTrue(winr.transfer(user1, 1000));
        winr.updateBlacklist(user1, true);

        vm.expectRevert("WINR: Sender is blacklisted");
        vm.prank(user1);
        address(winr).call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), user2, 500));
    }

    function testPauseAndUnpause() public {
        winr.pause();
        assertTrue(winr.paused());

        vm.expectRevert("WINR: Token transfers are paused");
        address(winr).call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), user1, 1000));

        winr.unpause();
        assertFalse(winr.paused());

        // Should work after unpause
        assertTrue(winr.transfer(user1, 1000));
        assertEq(winr.balanceOf(user1), 1000);
    }

    function testOnlyOwnerFunctions() public {
        vm.prank(user1);
        vm.expectRevert();
        winr.mint(user2, 1000);

        vm.prank(user1);
        vm.expectRevert();
        winr.burnFrom(user2, 1000);

        vm.prank(user1);
        vm.expectRevert();
        winr.updateBlacklist(user2, true);

        vm.prank(user1);
        vm.expectRevert();
        winr.pause();

        vm.prank(user1);
        vm.expectRevert();
        winr.unpause();
    }

    function testFuzzMint(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_SUPPLY - winr.totalSupply());

        uint256 initialSupply = winr.totalSupply();
        winr.mint(user1, amount);

        assertEq(winr.totalSupply(), initialSupply + amount);
        assertEq(winr.balanceOf(user1), amount);
    }

    function testFuzzBurn(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= winr.balanceOf(owner));

        uint256 initialSupply = winr.totalSupply();
        winr.burn(amount);

        assertEq(winr.totalSupply(), initialSupply - amount);
        assertEq(winr.balanceOf(owner), initialSupply - amount);
    }

    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= winr.balanceOf(owner));

        assertTrue(winr.transfer(user1, amount));

        assertEq(winr.balanceOf(user1), amount);
        assertEq(winr.balanceOf(owner), INITIAL_SUPPLY - amount);
    }
}
