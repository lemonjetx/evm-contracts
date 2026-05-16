// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LemonJet} from "../src/LemonJet.sol";
import {Vault} from "../src/Vault.sol";
import {HelperContract} from "./HelperContract.sol";
import {ILemonJet} from "../src/interfaces/ILemonJet.sol";
import {VRFV2PlusWrapperConsumerBase} from "../src/VRFV2PlusWrapperConsumerBase.sol";

import {MockLinkToken} from "@chainlink-contracts-1.2.0/src/v0.8/mocks/MockLinkToken.sol";

import {MockVRFV2PlusWrapper} from "./mocks/MockVRFV2PlusWrapperMock.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LemonJetTest is Test, HelperContract {
    address constant referralAddress = address(0x1005);
    address constant newReferralAddress = address(0x1006);
    address constant liquidityProvider = address(0x1007);
    ERC20Mock ljtToken;
    LemonJet ljtGame;

    MockLinkToken private s_linkToken;

    MockVRFV2PlusWrapper private s_wrapper;

    function setUp() public {
        s_linkToken = new MockLinkToken();
        s_wrapper = new MockVRFV2PlusWrapper(address(s_linkToken), address(1));
        ljtToken = new ERC20Mock();

        ljtGame = new LemonJet(address(s_wrapper), reserveFund, IERC20(address(ljtToken)), "Vault LemonJet", "VLJT");

        _fundAndApprove(ljtGame, liquidityProvider, 500 ether);
        vm.prank(liquidityProvider);
        ljtGame.deposit(500 ether, liquidityProvider);

        ljtToken.mint(player, 500 ether);
        vm.prank(player);
        ljtToken.approve(address(ljtGame), UINT256_MAX);
    }

    function testPlayLjt() public {
        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(1 ether, 150, referralAddress);
        uint256 requestId = s_wrapper.lastRequestId();

        address _player = ljtGame.requestIdToPlayer(requestId);

        (uint256 payout, uint256 potentialWinnings,, uint8 statusBeforeRelease) = ljtGame.latestGames(player);
        assertEq(payout, (1 ether * 150) / 100);
        assertEq(potentialWinnings, (1 ether * 50) / 100);
        assertEq(statusBeforeRelease, 1);
        assertEq(_player, player);

        vm.prank(address(s_wrapper));
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = UINT256_MAX;

        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        (,,, uint8 statusAfterRelease) = ljtGame.latestGames(player);

        assertEq(statusAfterRelease, 2);
    }

    function test_RevertWhen_PlayBeforeRelease() public {
        vm.startPrank(player);
        vm.deal(player, 2 ether);
        ljtGame.play{value: 1 ether}(1 ether, 150, referralAddress);
        vm.expectRevert(ILemonJet.AlreadyInGame.selector);
        ljtGame.play{value: 1 ether}(1 ether, 150, referralAddress);
        vm.stopPrank();
    }

    function testPlayLjt_WinPaysOutAndClearsRequest() public {
        uint256 bet = 1 ether;
        uint32 coef = 150;
        uint256 beforeBalance = ljtToken.balanceOf(player);

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef);
        uint256 requestId = s_wrapper.lastRequestId();

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;

        vm.prank(address(s_wrapper));
        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        uint256 payout = (bet * coef) / 100;
        uint256 afterBalance = ljtToken.balanceOf(player);
        assertEq(afterBalance, beforeBalance - bet + payout);

        (,,, uint8 status) = ljtGame.latestGames(player);
        assertEq(status, 2);
        assertEq(ljtGame.requestIdToPlayer(requestId), address(0));
    }

    function testPlayLjt_ReferrerDoesNotOverwrite() public {
        uint256 bet = 1 ether;
        uint32 coef = 150;

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef, referralAddress);
        uint256 requestId = s_wrapper.lastRequestId();

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = UINT256_MAX;

        vm.prank(address(s_wrapper));
        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        assertEq(ljtGame.getReferrer(player), referralAddress);

        uint256 referrerReward = (bet * 30) / 10_000;
        vm.prank(player);
        vm.deal(player, 1 ether);
        vm.expectEmit(true, true, false, true, address(ljtGame));
        emit ILemonJet.ReferrerRewardIssued(referralAddress, player, referrerReward);
        ljtGame.play{value: 1 ether}(bet, coef, newReferralAddress);

        assertEq(ljtGame.getReferrer(player), referralAddress);
    }

    function test_RevertWhen_BetBelowLimit() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(ILemonJet.BetAmountBelowLimit.selector, 1000));
        ljtGame.play(999, 150, referralAddress);
    }

    function test_RevertWhen_InvalidMultiplierBelowRange() public {
        vm.prank(player);
        vm.expectRevert(ILemonJet.InvalidMultiplier.selector);
        ljtGame.play(1000, 100, referralAddress);
    }

    function test_RevertWhen_InvalidMultiplierAboveRange() public {
        vm.prank(player);
        vm.expectRevert(ILemonJet.InvalidMultiplier.selector);
        ljtGame.play(1000, 5000_01, referralAddress);
    }

    function testPlayLjt_MaxMultiplierUsesHighPrecisionThreshold() public {
        uint256 bet = 1000;
        uint32 coef = 5000_00;

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef);

        (,, uint256 gameThreshold, uint8 status) = ljtGame.latestGames(player);
        assertEq(gameThreshold, 19_800);
        assertEq(status, 1);
    }

    function testPlayLjt_TracksPendingRiskAndClearsAfterWin() public {
        uint256 bet = 1 ether;
        uint32 coef = 150;

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef);
        uint256 requestId = s_wrapper.lastRequestId();

        assertEq(ljtGame.totalPendingPayouts(), 1.5 ether);
        assertEq(ljtGame.totalPendingWinnings(), 0.5 ether);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;

        vm.prank(address(s_wrapper));
        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        assertEq(ljtGame.totalPendingPayouts(), 0);
        assertEq(ljtGame.totalPendingWinnings(), 0);
    }

    function testPlayLjt_TracksPendingRiskAndClearsAfterLoss() public {
        uint256 bet = 1 ether;
        uint32 coef = 150;

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef);
        uint256 requestId = s_wrapper.lastRequestId();

        assertEq(ljtGame.totalPendingPayouts(), 1.5 ether);
        assertEq(ljtGame.totalPendingWinnings(), 0.5 ether);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 99_999_999;

        vm.prank(address(s_wrapper));
        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        assertEq(ljtGame.totalPendingPayouts(), 0);
        assertEq(ljtGame.totalPendingWinnings(), 0);
    }

    function test_RevertWhen_AggregateHalfKellyCapacityExceeded() public {
        address firstPlayer = address(0x1011);
        address secondPlayer = address(0x1012);
        address thirdPlayer = address(0x1013);
        uint256 bet = 1 ether;
        uint32 coef = 200;

        _fundAndApprove(ljtGame, firstPlayer, bet);
        _fundAndApprove(ljtGame, secondPlayer, bet);
        _fundAndApprove(ljtGame, thirdPlayer, bet);

        _play(ljtGame, firstPlayer, bet, coef);
        _play(ljtGame, secondPlayer, bet, coef);

        uint256 maxWin = ljtGame.maxWinAmount();
        assertEq(maxWin, 0.5 ether);
        assertEq(ljtGame.totalPendingPayouts(), 4 ether);
        assertEq(ljtGame.totalPendingWinnings(), 2 ether);

        vm.prank(thirdPlayer);
        vm.deal(thirdPlayer, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ILemonJet.BetAmountAboveLimit.selector, maxWin));
        ljtGame.play{value: 1 ether}(bet, coef);
    }

    function testPlayLjt_PendingBetPrincipalDoesNotIncreaseRiskCapacity() public {
        uint256 bet = 100 ether;
        uint32 coef = 1_01;

        vm.prank(player);
        vm.deal(player, 1 ether);
        ljtGame.play{value: 1 ether}(bet, coef);

        assertEq(ljtGame.totalPendingPayouts(), 101 ether);
        assertEq(ljtGame.totalPendingWinnings(), 1 ether);
        assertEq(ljtGame.maxWinAmount(), 1.5 ether);
    }

    function testPlayLjt_PendingPayoutsAreNotWithdrawable() public {
        LemonJet game =
            new LemonJet(address(s_wrapper), reserveFund, IERC20(address(ljtToken)), "Vault LemonJet", "VLJT");
        address secondLiquidityProvider = address(0x1014);
        address gamePlayer = address(0x1015);

        _fundAndApprove(game, secondLiquidityProvider, 500 ether);
        vm.prank(secondLiquidityProvider);
        game.deposit(500 ether, secondLiquidityProvider);

        _fundAndApprove(game, gamePlayer, 1 ether);
        _play(game, gamePlayer, 1 ether, 200);

        assertEq(game.totalPendingPayouts(), 2 ether);
        assertLe(game.maxWithdraw(secondLiquidityProvider), 499 ether);
        assertLe(game.previewRedeem(game.maxRedeem(secondLiquidityProvider)), 499 ether);
    }

    function test_RevertWhen_BetAboveLimit() public {
        vm.prank(address(ljtGame));
        assertTrue(ljtToken.transfer(address(10), 499 ether));

        uint256 bet = 1 ether;
        uint32 coef = 150;
        uint256 maxWin = ljtGame.maxWinAmount();

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(ILemonJet.BetAmountAboveLimit.selector, maxWin));
        ljtGame.play(bet, coef, referralAddress);
    }

    function test_RevertWhen_RawFulfillRandomWordsNotWrapper() public {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                VRFV2PlusWrapperConsumerBase.OnlyVRFWrapperCanFulfill.selector, address(this), address(s_wrapper)
            )
        );
        ljtGame.rawFulfillRandomWords(1, randomWords);
    }

    function test_RevertWhen_ConstructorReserveFundIsZero() public {
        vm.expectRevert(Vault.ZeroReserveFund.selector);
        new LemonJet(address(s_wrapper), address(0), IERC20(address(ljtToken)), "Vault LemonJet", "VLJT");
    }

    function test_RevertWhen_ConstructorAssetIsZero() public {
        vm.expectRevert(Vault.ZeroAsset.selector);
        new LemonJet(address(s_wrapper), reserveFund, IERC20(address(0)), "Vault LemonJet", "VLJT");
    }

    function test_RevertWhen_ConstructorAssetIsNotContract() public {
        address nonContractAsset = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(Vault.AssetNotContract.selector, nonContractAsset));
        new LemonJet(address(s_wrapper), reserveFund, IERC20(nonContractAsset), "Vault LemonJet", "VLJT");
    }

    function test_RevertWhen_ConstructorWrapperIsZero() public {
        vm.expectRevert(VRFV2PlusWrapperConsumerBase.ZeroVRFWrapper.selector);
        new LemonJet(address(0), reserveFund, IERC20(address(ljtToken)), "Vault LemonJet", "VLJT");
    }

    function test_RevertWhen_ConstructorWrapperIsNotContract() public {
        address nonContractWrapper = address(0xCAFE);

        vm.expectRevert(
            abi.encodeWithSelector(VRFV2PlusWrapperConsumerBase.VRFWrapperNotContract.selector, nonContractWrapper)
        );
        new LemonJet(nonContractWrapper, reserveFund, IERC20(address(ljtToken)), "Vault LemonJet", "VLJT");
    }

    function testClaimNativeBalanceTransfersToReserveFund() public {
        vm.deal(address(ljtGame), 2 ether);
        uint256 beforeReserveBalance = reserveFund.balance;

        ljtGame.claimNativeBalance();

        assertEq(reserveFund.balance, beforeReserveBalance + 2 ether);
        assertEq(address(ljtGame).balance, 0);
    }

    function testPlayLjt_RefundsExcessNativePayment() public {
        uint256 requestPrice = s_wrapper.calculateRequestPriceNative(100_000, 1);
        uint256 excess = 0.1 ether;
        vm.deal(player, requestPrice + excess);

        vm.prank(player);
        ljtGame.play{value: requestPrice + excess}(1000, 150);

        assertEq(player.balance, excess);
        assertEq(address(ljtGame).balance, 0);
    }

    function _fundAndApprove(LemonJet game, address account, uint256 amount) private {
        ljtToken.mint(account, amount);
        vm.prank(account);
        ljtToken.approve(address(game), UINT256_MAX);
    }

    function _play(LemonJet game, address account, uint256 bet, uint32 coef) private {
        vm.prank(account);
        vm.deal(account, 1 ether);
        game.play{value: 1 ether}(bet, coef);
    }
}
