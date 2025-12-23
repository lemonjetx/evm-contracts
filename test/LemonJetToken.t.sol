// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {LemonJetToken as LemonJetTokenCore} from "../src/LemonJetToken.sol";

contract LemonJetTokenTest is Test {
    LemonJetTokenCore token;

    address recipient = address(1);
    address owner = address(2);
    address nonOwner = address(3);

    function setUp() public {
        token = new LemonJetTokenCore(recipient, owner);
    }

    function testConstructorMintsInitialSupplyAndSetsOwner() public view {
        uint256 expectedSupply = 1_000_000_000 * 10 ** token.decimals();

        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(recipient), expectedSupply);
        assertEq(token.owner(), owner);
    }

    function testMintOnlyOwner() public {
        uint256 initialBalance = token.balanceOf(recipient);

        vm.prank(owner);
        token.mint(recipient, 10 ether);

        assertEq(token.balanceOf(recipient), initialBalance + 10 ether);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        token.mint(recipient, 1 ether);
    }
}
