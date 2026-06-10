// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {VRFV2PlusWrapperConsumerBase} from "./VRFV2PlusWrapperConsumerBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ILemonJet} from "./interfaces/ILemonJet.sol";
import {Vault} from "./Vault.sol";
import {Referral} from "./Referral.sol";

contract LemonJet is ILemonJet, ReentrancyGuardTransient, Referral, Vault, VRFV2PlusWrapperConsumerBase {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    uint8 private constant STARTED = 1;
    uint8 private constant RELEASED = 2;

    // foundry gas report estimates `rawFulfillRandomWords` above 50k in win/loss paths
    uint32 private constant CALLBACK_GAS_LIMIT = 100_000;
    // zero confirmations optimizes latency. If a request tx is reorged out,
    // the canonical coordinator/wrapper has no request commitment/callback, so it should not
    // fulfill that orphaned request
    uint16 private constant REQUEST_CONFIRMATIONS = 0;
    uint32 private constant NUM_WORDS = 1;

    uint256 private constant BASIS_POINT_SCALE = 100_00;
    uint256 private constant HOUSE_EDGE_BPS = 100;
    uint256 private constant HALF_KELLY_BPS = 50;
    uint256 private constant RANDOM_RANGE = 100_000_000;
    uint128 public totalPendingPayouts;
    uint128 public totalPendingWinnings;
    mapping(address => JetGame) public latestGames;
    mapping(uint256 => address) public requestIdToPlayer;

    // 1 storage slot
    struct JetGame {
        uint112 payout;
        uint104 potentialWinnings;
        uint32 threshold; // always less than RANDOM_RANGE
        uint8 status; // 0, 1, 2
    }

    constructor(
        //  VRF Wrapper 2.5 for Direct Funding
        address wrapperAddress,
        // EOA which receives a fee
        address _reserveFund,
        // ERC20 token for ERC4626 Vault
        IERC20 _asset,
        // Vault shares token name
        string memory _name,
        // Vault shares token symbol
        string memory _symbol
    ) Vault(_asset, _reserveFund, _name, _symbol) VRFV2PlusWrapperConsumerBase(wrapperAddress) {}

    function play(uint256 bet, uint32 coef, address referrer) external payable nonReentrant {
        referrer = _setReferrerIfNotExists(referrer);
        _play(bet, coef, referrer);
    }

    function play(uint256 bet, uint32 coef) external payable nonReentrant {
        address referrer = getReferrer(msg.sender);
        _play(bet, coef, referrer);
    }

    /// @param bet is amount of tokens to play
    /// @param coef is multiplier of bet
    /// @param referrer is address of referrer (optional)
    function _play(uint256 bet, uint32 coef, address referrer) private {
        require(bet >= 1000, BetAmountBelowLimit(1000)); // required precision to get 0.1% of bet
        require(coef >= 1_01 && coef <= 5000_00, InvalidMultiplier()); // 1.01 <= coef <= 5000.00
        uint256 payout = (bet * coef) / 100;
        uint256 potentialWinnings = payout - bet;
        uint256 gameThreshold = calcThresholdForCoef(coef);
        uint256 maxWin = maxWinAmount();
        require(potentialWinnings <= maxWin, BetAmountAboveLimit(maxWin));
        address player = msg.sender;
        JetGame storage game = latestGames[player];
        require(game.status != STARTED, AlreadyInGame()); // parallel games are not supported
        IERC20(asset()).safeTransferFrom(player, address(this), bet);
        (uint256 requestId, uint256 requestPrice) = _requestRandomWord();
        requestIdToPlayer[requestId] = player;

        // if referrer exists, issue vault shares by 0.3% of bet
        if (referrer != address(0)) {
            uint256 referrerReward = Math.mulDiv(bet, 30, BASIS_POINT_SCALE); // 0.3% of bet
            _mintByAssets(referrer, referrerReward);
            emit ReferrerRewardIssued(referrer, player, referrerReward);
        }

        // issue vault shares by 0.2% of bet
        uint256 reserveFundFee = Math.mulDiv(bet, 20, BASIS_POINT_SCALE); // 0.2% of bet
        _mintByAssets(reserveFund, reserveFundFee);

        _reservePendingRisk(payout, potentialWinnings);

        game.payout = payout.toUint112();
        game.potentialWinnings = potentialWinnings.toUint104();
        game.threshold = gameThreshold.toUint32();
        game.status = STARTED;

        _refundExcessNative(player, requestPrice);

        emit GameStarted(requestId, player, bet, coef);
    }

    function calcThresholdForCoef(uint256 coef) private pure returns (uint256) {
        return Math.mulDiv(RANDOM_RANGE, (BASIS_POINT_SCALE - HOUSE_EDGE_BPS) * 100, BASIS_POINT_SCALE * coef);
    }

    function maxWinAmount() public view returns (uint256) {
        uint256 maxAggregatePendingWinnings = Math.mulDiv(_settledBankroll(), HALF_KELLY_BPS, BASIS_POINT_SCALE);
        uint256 pendingWinnings = totalPendingWinnings;
        if (pendingWinnings >= maxAggregatePendingWinnings) return 0;
        return maxAggregatePendingWinnings - pendingWinnings;
    }

    function maxWithdraw(address owner) public view override(ERC4626) returns (uint256) {
        return Math.min(previewRedeem(super.maxRedeem(owner)), _withdrawableAssets());
    }

    function maxRedeem(address owner) public view override(ERC4626) returns (uint256) {
        uint256 shares = super.maxRedeem(owner);
        if (previewRedeem(shares) <= _withdrawableAssets()) return shares;
        return previewWithdraw(_withdrawableAssets());
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        _releaseGame(requestId, randomWords[0]);
    }

    function _releaseGame(uint256 requestId, uint256 randomNumber) private {
        // full trust in chainlink that needed data actualy exists
        address player = requestIdToPlayer[requestId];

        JetGame storage game = latestGames[player];
        uint256 gameThreshold = game.threshold;
        uint256 payout = game.payout;
        uint256 potentialWinnings = game.potentialWinnings;

        randomNumber = (randomNumber % RANDOM_RANGE) + 1;

        _releasePendingRisk(payout, potentialWinnings);

        // check if a player has won
        if (randomNumber <= gameThreshold) {
            /**
             * @dev See {Vault-_payoutWin}.
             */
            _payoutWin(player, payout);
        } else {
            payout = 0;
        }

        game.status = RELEASED;
        delete requestIdToPlayer[requestId];

        emit GameReleased(
            requestId,
            player,
            payout,
            randomNumber,
            Math.mulDiv(RANDOM_RANGE, (BASIS_POINT_SCALE - HOUSE_EDGE_BPS) * 100, BASIS_POINT_SCALE * randomNumber) // max profitable coef
        );
    }

    function _reservePendingRisk(uint256 payout, uint256 potentialWinnings) private {
        totalPendingPayouts = (uint256(totalPendingPayouts) + payout).toUint128();
        totalPendingWinnings = (uint256(totalPendingWinnings) + potentialWinnings).toUint128();
    }

    function _releasePendingRisk(uint256 payout, uint256 potentialWinnings) private {
        totalPendingPayouts -= payout.toUint128();
        totalPendingWinnings -= potentialWinnings.toUint128();
    }

    function _settledBankroll() private view returns (uint256) {
        return totalAssets() + totalPendingWinnings - totalPendingPayouts;
    }

    function _withdrawableAssets() private view returns (uint256) {
        uint256 assets = totalAssets();
        uint256 pendingPayouts = totalPendingPayouts;
        if (pendingPayouts >= assets) return 0;
        return assets - pendingPayouts;
    }

    function _requestRandomWord() private returns (uint256 requestId, uint256 requestPrice) {
        // // implimentation of the https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol#L21

        bytes memory extraArgs;
        assembly {
            extraArgs := mload(0x40)
            mstore(add(extraArgs, 0x04), 0x92fd1338) // EXTRA_ARGS_V1_TAG
            mstore(add(extraArgs, 0x24), 1) // ExtraArgsV1
            mstore(extraArgs, 0x24) //  36 bytes length selector (4 bytes) + bool (32 bytes)
            mstore(0x40, add(extraArgs, 0x60)) // update free pointer
        }

        requestPrice = i_vrfV2PlusWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS);

        require(msg.value >= requestPrice, FeeTooLow(requestPrice));

        requestId =
            requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, NUM_WORDS, extraArgs, requestPrice);
    }

    function _refundExcessNative(address player, uint256 requestPrice) private {
        uint256 refund = msg.value - requestPrice;
        if (refund == 0) return;
        payable(player).call{value: refund}("");
    }

    /// @notice sending accumulated native tokens to the `reserveFund`
    /// @dev `reserveFund` is EOA
    function claimNativeBalance() external {
        payable(reserveFund).transfer(address(this).balance);
    }
}
