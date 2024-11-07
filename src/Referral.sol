// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IReferral} from "./interfaces/IReferral.sol";

/// @title Referral contract
/// @notice set and stores who invited the player
/// @dev allowing the EOA or contract to set up only once a referrer address for `tx.origin`
contract Referral is IReferral {
    // referee => referrer
    mapping(address => address) private referrals;

    /// @dev `tx.origin` is used for new contracts so they can add referrals.
    function setReferrer(address referrer) external {
        require(referrer != address(0), ZeroAddressNotAllowed());
        require(referrals[tx.origin] == address(0), ReferrerAlreadySet());
        require(referrer != tx.origin, ReferrerEqualsReferee());
        referrals[tx.origin] = referrer;
        emit ReferrerSettled(tx.origin, referrer);
    }

    function getReferrer(address referee) external view returns (address) {
        return referrals[referee];
    }
}
