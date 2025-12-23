// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

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
            abi.encodeCall(VaultHarness.initialize, (IERC20(address(asset)), reserveFund, "LemonJet Vault", "VLJT"))
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

    function testPreviewWithdrawIncludesExitFee() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 fee = (assets * 60) / 1e4;
        uint256 expectedShares = assets + fee;
        uint256 previewShares = vault.previewWithdraw(assets);

        assertEq(previewShares, expectedShares);
    }

    function testPreviewRedeemDeductsExitFee() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 shares = 1 ether;
        uint256 expectedFee = (shares * 60) / (60 + 1e4);
        uint256 previewAssets = vault.previewRedeem(shares);

        assertEq(previewAssets, shares - expectedFee);
    }

    function testWithdrawMintsReserveFundFeeShares() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 shares = vault.withdraw(assets, player, player);
        uint256 sharesWithoutExitFee = (shares * 1e4) / (60 + 1e4);
        uint256 expectedReserveFee = (sharesWithoutExitFee * 10) / 1e4;

        assertEq(vault.balanceOf(reserveFund), expectedReserveFee);
    }

    function testRedeemMintsReserveFundFeeShares() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 shares = vault.balanceOf(player);
        vault.redeem(shares, player, player);

        uint256 sharesWithoutExitFee = (shares * 1e4) / (60 + 1e4);
        uint256 expectedReserveFee = (sharesWithoutExitFee * 10) / 1e4;

        assertEq(vault.balanceOf(reserveFund), expectedReserveFee);
    }

    function testMaxWinAmountUsesKellyCriteria() public {
        vault.deposit(10 ether, player);

        uint256 coef = 150;
        uint256 threshold = 6600;
        uint256 kelly = ((100 * (10_000 - threshold)) / (coef - 100)) - threshold;
        uint256 expectedMaxWin = (vault.totalAssets() * kelly) / 1e4;

        assertEq(vault.maxWinAmount(coef, threshold), expectedMaxWin);
    }
}
