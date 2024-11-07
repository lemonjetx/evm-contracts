// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IReferral {
    error ZeroAddressNotAllowed();

    error ReferrerAlreadySet();
    error ReferrerEqualsReferee();

    /**
     * @dev Emitted when `referee` aka `tx.origin` have set a `referrer` address
     */
    event ReferrerSettled(address indexed referee, address indexed referrer);

    function setReferrer(address referral) external;

    function getReferrer(address referee) external view returns (address);
}
