// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Vault} from "../src/Vault.sol";
import {HelperContract} from "./HelperContract.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract VaultTest is Test, HelperContract {
    ERC20Mock asset;
    Vault vault;

    function setUp() public {
        asset = new ERC20Mock();
        vault = new Vault(address(asset), reserveFund, "LemonJet Vault", "VLJT");
        asset.mint(player, 10 ether);
        vm.startPrank(player);
        asset.approve(address(vault), type(uint256).max);
    }

    function testDepositAndWithdraw() public {
        uint256 beforeDepositBalance = asset.balanceOf(player);

        vault.deposit(1 ether, player);
        console2.log(vault.balanceOf(player));
        vault.withdraw(vault.previewRedeem(vault.balanceOf(player)), player, player);

        uint256 afterWithdrawBalance = asset.balanceOf(player);

        assertEq(beforeDepositBalance > afterWithdrawBalance, true);
    }

    function testDepositAndGreaterWithdraw() public {
        uint256 beforeDepositBalance = asset.balanceOf(player);
        vault.deposit(1 ether, player);

        asset.mint(address(vault), 10 ether);

        vault.withdraw(10 ether, player, player);
        uint256 afterWithdrawBalance = asset.balanceOf(player);
        assertEq(beforeDepositBalance < afterWithdrawBalance, true);
    }
}
