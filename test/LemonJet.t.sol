// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LemonJet} from "../src/LemonJet.sol";
import {HelperContract} from "./HelperContract.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ILemonJet} from "../src/interfaces/ILemonJet.sol";
import {VRFV2PlusWrapperConsumerBaseUpgradeable} from "../src/VRFV2PlusWrapperConsumerBase.sol";

import {MockLinkToken} from "@chainlink-contracts-1.2.0/src/v0.8/mocks/MockLinkToken.sol";

import {MockVRFV2PlusWrapper} from "./mocks/MockVRFV2PlusWrapperMock.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LemonJetTest is Test, HelperContract {
    address constant referralAddress = address(5);
    address constant newReferralAddress = address(6);
    ERC20Mock ljtToken;
    ERC20Mock usdcToken;
    LemonJet ljtGame;

    MockLinkToken private s_linkToken;

    MockVRFV2PlusWrapper private s_wrapper;

    function setUp() public {
        s_linkToken = new MockLinkToken();
        s_wrapper = new MockVRFV2PlusWrapper(address(s_linkToken), address(1));
        ljtToken = new ERC20Mock();

        // Deploy implementation directly for coverage testing
        address implementation = address(new LemonJet());

        // Deploy UUPS proxy using UnsafeUpgrades (recommended for coverage tests)
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(
                LemonJet.initialize,
                (address(s_wrapper), reserveFund, IERC20(address(ljtToken)), "Vault LemonJet", "VLJT")
            )
        );

        ljtGame = LemonJet(proxy);

        ljtToken.mint(address(ljtGame), 500 ether);
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

        (uint256 potentialWinnings,, uint8 statusBeforeRelease) = ljtGame.latestGames(player);
        assertEq(potentialWinnings, (1 ether * 150) / 100);
        assertEq(statusBeforeRelease, 1);
        assertEq(_player, player);

        vm.prank(address(s_wrapper));
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = UINT256_MAX;

        ljtGame.rawFulfillRandomWords(requestId, randomWords);

        (,, uint8 statusAfterRelease) = ljtGame.latestGames(player);

        assertEq(statusAfterRelease, 2);
    }

    function test_RevertWhen_PlayBeforeRelease() public {
        vm.startPrank(player);
        vm.deal(player, 2 ether);
        ljtGame.play{value: 1 ether}(1 ether, 150, referralAddress);
        vm.expectRevert(abi.encodeWithSignature("AlreadyInGame()"));
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

        (,, uint8 status) = ljtGame.latestGames(player);
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

    function test_RevertWhen_BetAboveLimit() public {
        vm.prank(address(ljtGame));
        ljtToken.transfer(address(10), 499 ether);

        uint256 bet = 1 ether;
        uint32 coef = 150;
        uint256 gameThreshold = (1_000_000 / uint256(coef)) * 99 / 100;
        uint256 maxWin = ljtGame.maxWinAmount(coef, gameThreshold);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(ILemonJet.BetAmountAboveLimit.selector, maxWin));
        ljtGame.play(bet, coef, referralAddress);
    }

    function test_RevertWhen_RawFulfillRandomWordsNotWrapper() public {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                VRFV2PlusWrapperConsumerBaseUpgradeable.OnlyVRFWrapperCanFulfill.selector,
                address(this),
                address(s_wrapper)
            )
        );
        ljtGame.rawFulfillRandomWords(1, randomWords);
    }

    function testClaimNativeBalanceTransfersToReserveFund() public {
        vm.deal(address(ljtGame), 2 ether);
        uint256 beforeReserveBalance = reserveFund.balance;

        ljtGame.claimNativeBalance();

        assertEq(reserveFund.balance, beforeReserveBalance + 2 ether);
        assertEq(address(ljtGame).balance, 0);
    }
}
