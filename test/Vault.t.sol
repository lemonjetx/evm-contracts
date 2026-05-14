// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vault} from "../src/Vault.sol";
import {HelperContract} from "./HelperContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultTest is Test, HelperContract {
    uint256 private constant EXIT_FEE_BASIS_POINTS = 200;

    ERC20Mock asset;
    Vault vault;

    function setUp() public {
        asset = new ERC20Mock();
        vault = new Vault(IERC20(address(asset)), reserveFund, "LemonJet Vault", "VLJT");

        asset.mint(player, 10 ether);
        vm.startPrank(player);
        asset.approve(address(vault), type(uint256).max);
    }

    function testDepositAndWithdraw() public {
        uint256 beforeDepositBalance = asset.balanceOf(player);

        vault.deposit(1 ether, player);
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

        uint256 fee = (assets * EXIT_FEE_BASIS_POINTS) / 1e4;
        uint256 expectedShares = assets + fee;
        uint256 previewShares = vault.previewWithdraw(assets);

        assertEq(previewShares, expectedShares);
    }

    function testPreviewRedeemDeductsExitFee() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 shares = 1 ether;
        uint256 expectedFee = (shares * EXIT_FEE_BASIS_POINTS) / (EXIT_FEE_BASIS_POINTS + 1e4);
        uint256 previewAssets = vault.previewRedeem(shares);

        assertEq(previewAssets, shares - expectedFee);
    }

    function testWithdrawMintsReserveFundFeeShares() public {
        uint256 assets = 2 ether;
        vault.deposit(assets, player);

        uint256 withdrawnAssets = 1 ether;
        uint256 shares = vault.withdraw(withdrawnAssets, player, player);
        uint256 sharesWithoutExitFee = (shares * 1e4) / (EXIT_FEE_BASIS_POINTS + 1e4);
        uint256 expectedReserveFee = (sharesWithoutExitFee * 10) / 1e4;

        assertEq(vault.balanceOf(reserveFund), expectedReserveFee);
    }

    function testRedeemMintsReserveFundFeeShares() public {
        uint256 assets = 1 ether;
        vault.deposit(assets, player);

        uint256 shares = vault.balanceOf(player);
        vault.redeem(shares, player, player);

        uint256 sharesWithoutExitFee = (shares * 1e4) / (EXIT_FEE_BASIS_POINTS + 1e4);
        uint256 expectedReserveFee = (sharesWithoutExitFee * 10) / 1e4;

        assertEq(vault.balanceOf(reserveFund), expectedReserveFee);
    }

    function test_RevertWhen_ConstructorReserveFundIsZero() public {
        vm.expectRevert(Vault.ZeroReserveFund.selector);
        new Vault(IERC20(address(asset)), address(0), "LemonJet Vault", "VLJT");
    }

    function test_RevertWhen_ConstructorAssetIsZero() public {
        vm.expectRevert(Vault.ZeroAsset.selector);
        new Vault(IERC20(address(0)), reserveFund, "LemonJet Vault", "VLJT");
    }

    function test_RevertWhen_ConstructorAssetIsNotContract() public {
        address nonContractAsset = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(Vault.AssetNotContract.selector, nonContractAsset));
        new Vault(IERC20(nonContractAsset), reserveFund, "LemonJet Vault", "VLJT");
    }
}
