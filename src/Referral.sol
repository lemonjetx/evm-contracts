// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IReferral} from "./interfaces/IReferral.sol";

/// @title Referral contract
/// @notice set and stores who invited the player
/// @dev allowing the EOA or contract to set up only once a referrer address for `msg.sender`
contract Referral is IReferral {
    // referee => referrer
    mapping(address => address) private referrals;

    /// @dev `msg.sender` is used for new contracts so they can add referrals.
    function setReferrer(address referrer) public {
        address referee = msg.sender;
        require(referrals[referee] == address(0), ReferrerAlreadySet());

        _setReferrer(referee, referrer);
    }

    function getReferrer(address referee) public view returns (address) {
        return referrals[referee];
    }

    /// @param referrer_ can only be set once
    function _setReferrerIfNotExists(address referrer_) internal returns (address) {
        address referee = msg.sender;
        address referrer = referrals[referee];
        if (referrer == address(0)) {
            _setReferrer(referee, referrer_);
            return referrer_;
        }
        return referrer;
    }

    function _setReferrer(address referee, address referrer) internal {
        require(referee != referrer, ReferrerEqualsReferee());
        require(referrer != address(0), ZeroAddressNotAllowed());

        referrals[referee] = referrer;
        emit ReferrerSettled(referee, referrer);
    }
}
