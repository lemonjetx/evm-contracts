// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LemonJetTokenUpgradeable} from "../src/LemonJetTokenUpgradeable.sol";

contract LemonJetTokenTest is Test {
    LemonJetTokenUpgradeable token;

    address recipient = address(1);
    address owner = address(2);
    address nonOwner = address(3);
    uint256 mintAmount = 10 ether;

    function setUp() public {
        address implementation = address(new LemonJetTokenUpgradeable());
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(LemonJetTokenUpgradeable.initialize, (recipient, owner, mintAmount))
        );
        token = LemonJetTokenUpgradeable(proxy);
    }

    function testInitializeMintsInitialSupplyAndSetsOwner() public view {
        uint256 expectedSupply = 1_000_000_000 * 10 ** token.decimals();

        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(recipient), expectedSupply);
        assertEq(token.owner(), owner);
        assertEq(token.mintAmount(), mintAmount);
    }

    function testMintOnlyOwner() public {
        uint256 initialBalance = token.balanceOf(recipient);

        vm.prank(owner);
        token.mint(recipient, 10 ether);

        assertEq(token.balanceOf(recipient), initialBalance + 10 ether);

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        token.mint(recipient, 1 ether);
    }
}
