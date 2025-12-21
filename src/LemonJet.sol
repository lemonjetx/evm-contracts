// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VRFV2PlusWrapperConsumerBase} from
    "@chainlink-contracts-1.2.0/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ILemonJet} from "./interfaces/ILemonJet.sol";
import {Vault} from "./Vault.sol";
import {Referral} from "./Referral.sol";

contract LemonJet is ILemonJet, Referral, Vault, VRFV2PlusWrapperConsumerBase {
    using SafeERC20 for IERC20;

    uint8 private constant STARTED = 1;
    uint8 private constant RELEASED = 2;

    uint256 private constant houseEdge = 1; // %
    uint256 private constant threshold = 1e6;
    mapping(address => JetGame) public latestGames;
    mapping(uint256 => address) public requestIdToPlayer;


    // 1 storage slot
    struct JetGame {
        uint224 payout;
        uint24 threshold; // always less than threshold (1_000_000)
        uint8 status; // 0, 1, 2
    }

    constructor(
        //  VRF Wrapper 2.5 for Direct Funding
        address wrapperAddress,
        // EOA which receives a fee
        address _reserveFund,
        // ERC20 token for ERC4626 Vault
        address _asset,
        // Vault shares token name
        string memory _name,
        // Vault shares token symbol
        string memory _symbol
    ) VRFV2PlusWrapperConsumerBase(wrapperAddress) Vault(_asset, _reserveFund, _name, _symbol) {}

    function play(uint256 bet, uint32 coef, address referrer) external payable {
        referrer = _setReferrerIfNotExists(referrer);
        _play(bet, coef, referrer);
    }

    function play(uint256 bet, uint32 coef) external payable {
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
        uint256 maxWin = maxWinAmount(coef, gameThreshold);
        require(potentialWinnings <= maxWin, BetAmountAboveLimit(maxWin));
        address player = msg.sender;
        require(latestGames[player].status != STARTED, AlreadyInGame()); // parallel games are not supported
        IERC20(asset()).safeTransferFrom(player, address(this), bet);
        uint256 requestId = _requestRandomWord();
        requestIdToPlayer[requestId] = player;
        latestGames[player] = JetGame(uint224(payout), uint24(gameThreshold), STARTED);

        // if referrer exists, issue vault shares by 0.3% of bet
        if (referrer != address(0)) {
            uint256 referrerReward = Math.mulDiv(bet, 30, 10_000); // 0.3% of bet
            _mintByAssets(referrer, referrerReward);
            emit ReferrerRewardIssued(referrer, player, referrerReward);
        }

        // issue vault shares by 0.2% of bet
        uint256 reserveFundFee = Math.mulDiv(bet, 20, 10_000); // 0.2% of bet
        _mintByAssets(reserveFund, reserveFundFee);

        emit GameStarted(requestId, player, bet, coef);
    }

    function calcThresholdForCoef(uint256 coef) private pure returns (uint256) {
        uint256 baseThreshold = threshold / coef;
        uint256 adjustedThreshold = (baseThreshold * (100 - houseEdge)) / 100;
        return adjustedThreshold;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        _releaseGame(requestId, randomWords[0]);
    }

    function _releaseGame(uint256 requestId, uint256 randomNumber) private {
        // full trust in chainlink that needed data actualy exists
        address player = requestIdToPlayer[requestId];
        JetGame memory game = latestGames[player];
        uint256 payout = game.payout;
        uint256 gameThreshold = game.threshold;

        randomNumber = (randomNumber % 10_000) + 1;

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
            (threshold * (100 - houseEdge)) / 100 / randomNumber // the maximum coef that could win and give profit
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

        // foundry gas report estimate the `rawFulfillRandomWords` at 47738
        // zero block confirmations need to get a random number as fast as possible because and chain reorganization can't negatively affect
        (requestId,) = requestRandomnessPayInNative(50_000, 0, 1, extraArgs);
    }


    /// @notice sending accumulated native tokens to the `reserveFund`
    /// @dev `reserveFund` is EOA
    function claimNativeBalance() external {
        payable(reserveFund).transfer(address(this).balance);
    }
}
