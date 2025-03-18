// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract ReclaimTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotBuyer() public {}
    function test_reverts_ifBeforeCaptureDeadline() public {}
    function test_reverts_ifAuthorizedValueIsZero() public {}
    function test_reverts_ifFundsAreNotTransferred() public {}
    function test_succeeds_ifCalledByBuyerAfterCaptureDeadline() public {}
    function test_emitsExpectedEvents() public {}
}