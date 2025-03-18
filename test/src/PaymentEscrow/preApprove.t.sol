// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotBuyer() public {}
    function test_reverts_ifPaymentIsAlreadyAuthorized() public {}
    function test_succeeds_ifCalledByBuyer() public {}
    function test_emitsExpectedEvents() public {}
}