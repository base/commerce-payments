// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RefundWithSponsorTest is PaymentEscrowBase {
    function test_reverts_ifValueIsZero() public {}
    function test_reverts_ifSenderIsInvalid() public {}
    function test_reverts_ifValueIsGreaterThanCaptured() public {}
    function test_reverts_ifSignatureIsInvalid() public {}
    function test_reverts_ifSaltIsIncorrect() public {}
    function test_reverts_ifSponsorIsIncorrect() public {}
    function test_reverts_ifRefundDeadlineIsIncorrect() public {}
    function test_reverts_ifValueIsNotTransferred() public {}
    function test_succeeds_ifCalledByOperator() public {}
    function test_succeeds_ifCalledByCaptureAddress() public {}
    function test_emitsExpectedEvents() public {}
}