// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    // foundry gas report estimate the `rawFulfillRandomWords` at 47738
    uint32 private constant CALLBACK_GAS_LIMIT = 50_000;
    // zero block confirmations need to get a random number as fast as possible because and chain reorganization can't negatively affect
    uint16 private constant REQUEST_CONFIRMATIONS = 0;
    uint32 private constant NUM_WORDS = 1;

    uint256 private constant HOUSE_EDGE_PERCENT = 1;
    uint256 private constant RANDOM_RANGE = 100_000_000;
    mapping(address => JetGame) public latestGames;
    mapping(uint256 => address) public requestIdToPlayer;

    // 1 storage slot
    struct JetGame {
        uint216 payout;
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
        uint256 requestId = _requestRandomWord();
        requestIdToPlayer[requestId] = player;

        // if referrer exists, issue vault shares by 0.3% of bet
        if (referrer != address(0)) {
            uint256 referrerReward = Math.mulDiv(bet, 30, 10_000); // 0.3% of bet
            _mintByAssets(referrer, referrerReward);
            emit ReferrerRewardIssued(referrer, player, referrerReward);
        }

        // issue vault shares by 0.2% of bet
        uint256 reserveFundFee = Math.mulDiv(bet, 20, 10_000); // 0.2% of bet
        _mintByAssets(reserveFund, reserveFundFee);

        game.payout = payout.toUint216();
        game.threshold = gameThreshold.toUint32();
        game.status = STARTED;

        emit GameStarted(requestId, player, bet, coef);
    }

    function calcThresholdForCoef(uint256 coef) private pure returns (uint256) {
        return Math.mulDiv(RANDOM_RANGE, 100 - HOUSE_EDGE_PERCENT, coef);
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

        randomNumber = (randomNumber % RANDOM_RANGE) + 1;

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
            Math.mulDiv(RANDOM_RANGE, 100 - HOUSE_EDGE_PERCENT, randomNumber) // max profitable coef
        );
    }

    function _requestRandomWord() private returns (uint256 requestId) {
        // // implimentation of the https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol#L21

        bytes memory extraArgs;
        assembly {
            extraArgs := mload(0x40)
            mstore(add(extraArgs, 0x04), 0x92fd1338) // EXTRA_ARGS_V1_TAG
            mstore(add(extraArgs, 0x24), 1) // ExtraArgsV1
            mstore(extraArgs, 0x24) //  36 bytes length selector (4 bytes) + bool (32 bytes)
            mstore(0x40, add(extraArgs, 0x60)) // update free pointer
        }

        uint256 requestPrice = i_vrfV2PlusWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS);

        require(msg.value >= requestPrice, FeeTooLow(requestPrice));

        requestId =
            requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, NUM_WORDS, extraArgs, requestPrice);
    }

    /// @notice sending accumulated native tokens to the `reserveFund`
    /// @dev `reserveFund` is EOA
    function claimNativeBalance() external {
        payable(reserveFund).transfer(address(this).balance);
    }
}
