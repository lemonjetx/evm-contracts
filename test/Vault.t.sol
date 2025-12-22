// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Vault} from "../src/Vault.sol";
import {VaultHarness} from "./mocks/VaultHarness.sol";
import {HelperContract} from "./HelperContract.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract VaultTest is Test, HelperContract {
    ERC20Mock asset;
    Vault vault;

    function setUp() public {
        asset = new ERC20Mock();

        // Deploy VaultHarness implementation (which has initializer entry point)
        address implementation = address(new VaultHarness());

        // Deploy UUPS proxy using UnsafeUpgrades (recommended for coverage tests)
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(
                VaultHarness.initialize,
                (IERC20(address(asset)), reserveFund, "LemonJet Vault", "VLJT")
            )
        );

        vault = Vault(proxy);

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
