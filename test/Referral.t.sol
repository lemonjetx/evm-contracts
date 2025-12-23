// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HelperContract} from "./HelperContract.sol";
import {Referral} from "../src/Referral.sol";
import {IReferral} from "../src/interfaces/IReferral.sol";

contract ReferralTest is Test, HelperContract {
    Referral referral;
    address referrer = address(5);
    address referee = address(6);

    function setUp() public {
        referral = new Referral();
    }

    function testSetReferralIfNotExists() public {
        vm.prank(referee);
        vm.expectEmit(true, true, false, true);
        emit IReferral.ReferrerSettled(referee, referrer);
        referral.setReferrer(referrer);

        assertEq(referral.getReferrer(referee), referrer);
    }

    function testGetReferrerDefaultsToZero() public view {
        assertEq(referral.getReferrer(referee), address(0));
    }

    function test_RevertWhen_ReferrerAlreadySet() public {
        vm.prank(referee);
        referral.setReferrer(referrer);

        vm.prank(referee);
        vm.expectRevert(IReferral.ReferrerAlreadySet.selector);
        referral.setReferrer(address(7));
    }

    function test_RevertWhen_ReferrerEqualsReferee() public {
        vm.prank(referee);
        vm.expectRevert(IReferral.ReferrerEqualsReferee.selector);
        referral.setReferrer(referee);
    }

    function test_RevertWhen_ReferrerIsZeroAddress() public {
        vm.prank(referee);
        vm.expectRevert(IReferral.ZeroAddressNotAllowed.selector);
        referral.setReferrer(address(0));
    }
}
