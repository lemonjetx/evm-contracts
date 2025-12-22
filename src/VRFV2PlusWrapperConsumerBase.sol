// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {LinkTokenInterface} from "@chainlink-contracts-1.2.0/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IVRFV2PlusWrapper} from "@chainlink-contracts-1.2.0/src/v0.8/vrf/dev/interfaces/IVRFV2PlusWrapper.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract VRFV2PlusWrapperConsumerBaseUpgradeable is Initializable {
  error OnlyVRFWrapperCanFulfill(address have, address want);

  IVRFV2PlusWrapper public i_vrfV2PlusWrapper;

  /**
   * @param _vrfV2PlusWrapper is the address of the VRFV2Wrapper contract
   */
  function initialize(address _vrfV2PlusWrapper) internal onlyInitializing {
    i_vrfV2PlusWrapper = IVRFV2PlusWrapper(_vrfV2PlusWrapper);
  }

  // solhint-disable-next-line chainlink-solidity/prefix-internal-functions-with-underscore
  function requestRandomnessPayInNative(
    uint32 _callbackGasLimit,
    uint16 _requestConfirmations,
    uint32 _numWords,
    bytes memory extraArgs
  ) internal returns (uint256 requestId, uint256 requestPrice) {
    requestPrice = i_vrfV2PlusWrapper.calculateRequestPriceNative(_callbackGasLimit, _numWords);
    return (
      i_vrfV2PlusWrapper.requestRandomWordsInNative{value: requestPrice}(
        _callbackGasLimit,
        _requestConfirmations,
        _numWords,
        extraArgs
      ),
      requestPrice
    );
  }

  /**
   * @notice fulfillRandomWords handles the VRF V2 wrapper response. The consuming contract must
   * @notice implement it.
   *
   * @param _requestId is the VRF V2 request ID.
   * @param _randomWords is the randomness result.
   */
  // solhint-disable-next-line chainlink-solidity/prefix-internal-functions-with-underscore
  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal virtual;

  function rawFulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) external {
    address vrfWrapperAddr = address(i_vrfV2PlusWrapper);
    if (msg.sender != vrfWrapperAddr) {
      revert OnlyVRFWrapperCanFulfill(msg.sender, vrfWrapperAddr);
    }
    fulfillRandomWords(_requestId, _randomWords);
  }

  /// @notice getBalance returns the native balance of the consumer contract
  function getBalance() public view returns (uint256) {
    return address(this).balance;
  }
}