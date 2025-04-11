// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";

contract ERC3009PaymentCollectorTest is PaymentEscrowBase {
    function test_collect_reverts_whenNotOperator(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, amount);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        erc3009PaymentCollector.collectTokens(paymentInfo, amount, "");
    }
}
